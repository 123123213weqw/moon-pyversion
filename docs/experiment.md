# 差分实验：设计

本文说明"Moon PyVersion 与 PyPA `packaging` 行为一致"这句话是如何被检验的。
所有步骤都在仓库里、用固定输入、可重复执行。

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

`pypi` 语料由 `tools/fetch_pypi_corpus.py` 生成：抓取 97 个知名包的元数据，
每包最多取 60 个版本（轮转、按字典序），去重排序后写成
`fixtures/pypi_corpus.mbt`。抓取脚本同时写出 `fixtures/pypi_corpus.json`
记录来源与每个包的抓取结果，便于核对。

## 记录类型（六种）

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

- oracle 是同一门语言的另一个实现，不是规范本身；两者同时误解规范的可能
  性无法排除。
- 语料是抽样的：PyPI 上的版本与约束远多于此处收录的量。
- 只覆盖版本与约束本身；不覆盖包名规范化、环境标记、平台标签、依赖求解。
- 计时（`examples/bench`）是单机单后端的墙钟数字，不是跨语言基准。
