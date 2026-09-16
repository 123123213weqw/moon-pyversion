# 差分实验：设计

本文说明"Moon PyVersion 与 PyPA `packaging` 行为一致"这句话是如何被检验的。
所有步骤都在仓库里、用固定输入、可重复执行。

本文说的是**设计**（为什么这样对照、输入从哪来）；跑出来的**数字**在
[experiment-results.md](experiment-results.md)；整套测试的分层、覆盖矩阵与
复现命令在 [test-report.md](test-report.md)。

## 为什么需要独立 oracle

本库是 PEP 440 的一种实现，而 PEP 440 的自然语言规范留有余地（预发布默认
策略、`~=` 上界、`===` 的匹配对象）。只靠自写测试无法证明"与生态一致"，
只能证明"与自己的理解一致"。因此引入 CPython 的 `packaging` 作为**独立
oracle**：它由另一个团队用另一门语言实现，且是 pip / setuptools 实际使用
的实现。

oracle 只在测试期运行，不出现在 MoonBit 库的依赖里（`moon.mod` 仅
`moonbitlang/core`）。

## 语料来源（四条，互补）

| 来源 | 规模 | 作用 |
| --- | --- | --- |
| `curated` | 81 个版本 × 47 条约束 | 手工挑选的 PEP 440 角落：epoch、别名、隐式 post/dev、local、边界排除规则 |
| `generated` | 4000 个版本、700 条约束 | 按 PEP 440 文法随机组合生成，覆盖 curated 没想到的组合 |
| `mutated` | 3000 个版本、1244 条约束 | 对上述合法串做单字符替换/删除/插入，外加固定垃圾串，用来压拒绝行为 |
| `pypi` | 3000 个真实版本、500 条真实约束、600 条真实需求行、900 个真实文件名 | 来自 PyPI JSON API（`releases`、`Requires-Dist`、`Requires-Python`、`urls[].filename`），见 `fixtures/` |
| `pypi`（元数据/索引） | 239 份真实 `METADATA`、97 份真实 PEP 691 索引响应 | 真实 wheel 的 PEP 658 边上文件；公开索引的 JSON 响应，见 `fixtures/metadata_corpus.mbt`、`fixtures/index_corpus.mbt` |
| `curated`（文档类） | 83 个 TOML 文档、46 条元数据规则样例、21 个索引文档、114 份手工锁文件 + 6 份 `uv` 锁文件 | 规范本身：TOML 1.0、核心元数据、PEP 691、PEP 751 |

`pypi` 语料由 `tools/fetch_pypi_corpus.py` 生成：抓取 97 个知名包的元数据，
每包最多取 60 个版本（轮转、按字典序），去重排序后写成
`fixtures/pypi_corpus.mbt`。抓取脚本同时写出 `fixtures/pypi_corpus.json`
记录来源与每个包的抓取结果，便于核对。

## 记录类型（26 种）

| 记录 | 语义 |
| --- | --- |
| `parse` | 解析 + 规范化：接受/拒绝，以及规范化后的字符串 |
| `spec` | 约束字符串是否可解析 |
| `cmp` | 两个版本的排序符号 |
| `contains` | `spec.contains(version)`，三种预发布模式 |
| `filter` | `SpecifierSet::filter(candidates, spec)` 的保序结果 |
| `order` | 对整批候选排序是否真的升序 |
| `canon` | 名称规范化，以及版本键/显示两种形式 |
| `file` | 分发文件名：wheel / sdist / 其他扩展名，各自解析结果 |
| `req` | PEP 508 需求行：名称、extras、约束、URL、marker |
| `marker` | 标记的接受与规范渲染 |
| `marker_env` | 环境表定义（输入，不是断言） |
| `marker_eval` | 标记在指定环境上的取值 |
| `toml` | TOML 1.0 文档：参考读取器的裁决 + 库的规范重序列化 |
| `license` | PEP 639 许可证表达式的规范化 |
| `meta` | `METADATA` / `PKG-INFO`：裁决、错误码、规范重渲染 |
| `meta_values` | 同一份文档的**逐值**比对（名称、版本、Keywords 分段、Provides-Extra、Requires-Python、Requires-Dist 条数、Summary 有无） |
| `meta_divergence` | 声明分歧（输入，不是断言） |
| `index` | PEP 691 文档：裁决 + 投影 |
| `index_dir` | 目录扫描的分类与排序 |
| `index_divergence` | 声明分歧（输入，不是断言） |
| `resolve` | 候选选择与排序、每个被拒文件的**首条**失败规则 |
| `tag` | PEP 425 标签生成：一组参数 → 有序标签表（`cpython` / `generic` /
  `pure` / `compatible` / `mac` / `select` 六种模式） |
| `tag_divergence` | 声明分歧（输入，不是断言） |
| `upgrade` | 升级短名单：给定参数 → 待测版本表 + 每个被弃候选的规则 |
| `pylock` | PEP 751 文档：裁决 + 投影（成员、文件记录、适用性） |
| `pylock_divergence` | 声明分歧（输入，不是断言） |

其中 **21 种是断言**（每条都有一条外部对照），另外 5 种是输入与声明分歧
（`marker_env`、`meta_divergence`、`index_divergence`、`tag_divergence`、
`pylock_divergence`），harness 只断言它们的方向，不断言"哪一侧对"。

预发布模式 `auto`/`any`/`none` 分别对应 `packaging` 的 `None`/`True`/`False`，
这是库对外暴露的 `prereleases? : Bool?` 参数。

## 执行链路

```
examples/diff (MoonBit, 四个后端)
        │  制表符分隔的 records（确定性）
        ▼
tools/diff_packaging.py ──► 逐条回放给 packaging，按来源/类型/模式分组报告
        ▲
        │  同一份捕获结果
tools/oracle_matrix.py ──► 在多个 packaging 版本上回放，输出漂移矩阵
tools/target_parity.py ──► 只比较四个后端输出的 sha256
tools/mutation_probe.py ─► 注入故意缺陷，断言上面的对照能报错
```

**变异探针**是这套实验的元检查：如果注入缺陷后 harness 仍然是绿的，
说明语料没覆盖那段行为，绿是无意义的。因此每个里程碑都要保证新增记录
能被变异探针覆盖（见 experiment-results.md 第 5.5 节）。

## 三点设计约束

1. **确定性**：生成器是常量种子的 64 位 LCG，不读时钟、不读环境、不联网，
   整数运算全部回绕；同一份源码在 wasm/wasm-gc/js/native 上必须输出逐字节
   相同的语料。`tools/target_parity.py` 就是这条约束的检查。
2. **可复现**：`tools/fetch_pypi_corpus.py` 重复运行结果逐字节相同；语料本身
   已提交，评审不需要联网也能重跑全部差分。
3. **不掩盖失败**：`tools/diff_packaging.py` 在有不一致时退出码为 1，并打印
   样本；只有 `--input` 复用旧捕获、或显式传 `--tolerate-policy-drift`
   时，非目标版本的差异才被降级为"漂移"单独统计。

## 已知且被测量的偏差

库固定对齐 `packaging 26.3`。上游在 26.3 改变了 compatible release
（`~=`）的上界算法，也调整过预发布默认策略，因此旧版本 oracle 必然出现
差异。这些差异**不被隐藏**：`tools/oracle_matrix.py` 会把它们连同原因分类
一起打印出来，目标版本（26.3）必须 0 差异。数据见
[experiment-results.md](experiment-results.md)。

## 局限

- oracle 是另一份实现，不是规范本身；两者同时误解规范的可能性无法排除。
- **不是所有记录都有外部 oracle**。`packaging` 覆盖版本、约束、文件名、
  需求行、标记、许可证与核心元数据；TOML 的裁决来自 `tomli`；而
  PEP 691 的索引文档、离线目录扫描、候选选择与 PEP 751 锁文件**没有**现成的
  Python 参考实现，这几类记录对照的是**本仓库按规范另写的一份实现**（分别写在
  `tools/fetch_index_corpus.py` 与 `tools/fetch_pylock_corpus.py` 里，PEP 751 的
  那份连"对照物是别人写的"都做不到，见 experiment-results.md 6.9：语料里唯一不
  由本仓库生成的输入是 `pylock_cases/uv/` 那 6 份 `uv` 写出的锁文件，而 `uv` 只写
  不读、不给出裁决）。它们能
  抓出"库与规范不一致"，抓不出"两份实现同时读错同一段规范"。这一点写在每类记录
  的说明里，不当作等价于 0 不一致的强证据。
- 语料是抽样的：PyPI 上的版本与约束远多于此处收录的量。
- 平台标签的**计算**已实现（`tags.mbt`，PEP 425），但**宿主探测不做**：
  `sys_tags()` 与 `platform_tags()` 要靠 `sys.version_info`、`sysconfig`、
  `EXT_SUFFIX` 和运行中的 libc，这些仍然只由调用方提供；库计算的是"给定
  解释器、ABI 与平台表"之后的展开与排序，`tag` 记录逐条对照 `packaging.tags`
  （见 experiment-results.md 6.12）。依赖求解、下载与安装不做。
- 计时（`examples/bench`）是单机单后端的墙钟数字，不是跨语言基准。
