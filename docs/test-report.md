# Moon PyVersion 测试报告

**被测对象**：`123123213weqw/moon_pyversion`（`moon.mod` 版本 0.2.0，Apache-2.0）
**仓库**：https://github.com/123123213weqw/moon-pyversion
**报告依据**：M13 的历史基线；新增 M14 双包审计的验证见本报告末尾补记。
下表所有数字由同一次验证运行（四后端 + 差分 + 探针 + fixture 自检）产出
**工具链**：`moon 0.1.20260904`（moonc v0.10.12）、CPython 3.10.12、
oracle 侧 `packaging==26.3` / `tomli==2.4.1`
**测试后端**：wasm / wasm-gc / js / native 四个目标各跑一遍

---

## 0. 一句话结论

核心路径有 **293 个测试块**，四个后端各自全通过（293 × 4 = **1 172 次**）；
另有 **122 640 条**确定性差分记录逐条回放给独立实现 `packaging==26.3`，
**0 不一致**；并且用 **43 处故意注入的缺陷**证明这份「0 不一致」不是因为对照失效
（43/43 全部被检出）。测试过程中查出并修复了 **13 处库的真实缺陷**（其中 6 处是
PEP 751 里比规范松的放宽）、**4 处测试基础设施缺陷**与 **1 处语料漏洞**，
每一处都补了回归测试、语料样例或变异探针。

---

## 1. 测试目标与原则

这个库不联网、不读文件系统、不读运行时环境，因此**测试不能用「跑起来看看对不对」
的方式**。三条原则决定了整套测试的形状：

1. **结论必须可失败地验证**。「0 不一致」只有在「对照能报错」时才有意义，所以除了
   正向对照，还必须有一层**主动注入缺陷**的验证（§4）。
2. **输入必须可复现**。所有真实语料（PyPI 元数据、索引响应、`uv` 锁文件）以
   文本形式入库，语料的生成器有 `--check` 自检（§7），确保 fixture 不是手改来的、
   也不是旧版生成器留下的。
3. **不读宿主**。凡是需要宿主事实的接口，宿主事实都由调用方注入；测试因此可以在
   四个后端给出**逐字节相同**的结果（§6），这一点本身也是被测对象。

---

## 2. 测试分层

| 层 | 内容 | 规模 | 参照物 |
| --- | --- | ---: | --- |
| 1 单元测试 | 每个模块的规则、边界、非法输入、稳定错误码 | 293 个测试块 | 规范正文 + 手工推导 |
| 2 差分实验 | 确定性语料逐条回放 | 122 640 条记录 | CPython `packaging==26.3`（独立黑盒） |
| 3 规范对照 | 无现成实现的几类，按规范另写第二份读法 | `toml` 83、`index` 118、`pylock` 215、`tag` 62、`upgrade` 51 | `tomli 2.4.1`、规范正文、`packaging.tags`、`SpecifierSet.filter` |
| 4 变异探针 | 向库里注入缺陷，断言语料必须报错 | 43 处注入 | 语料本身 |
| 5 多版本漂移 | 同一份语料在 4 个 `packaging` 版本上回放 | 4 × 122 640 | 24.2 / 25.0 / 26.0 / 26.3 |
| 6 四后端一致性 | 同一输入的输出逐字节比对 | 语料 + 4 个场景报告 | 后端之间互比 |
| 7 fixture 自检 | fixture 是否等于生成器当前的输出 | 7 份 fixture | 生成器自身 |

### 2.1 单元测试（293 个测试块）

| 测试文件 | 测试块 | 覆盖的模块（源码行数） |
| --- | ---: | --- |
| `version_test.mbt` | 15 | `version.mbt`（553）：PEP 440 规范化、epoch、pre/post/dev、local、比较 |
| `specifier_test.mbt` | 11 | `specifier.mbt`（394）：七种操作符、通配、预发布边界、`filter` |
| `utils_test.mbt` | 14 | `utils.mbt`（375）：PEP 503 名称、版本键、wheel/sdist 文件名、标签解析 |
| `requirements_test.mbt` | 13 | `requirements.mbt`（411）：PEP 508 需求行 |
| `markers_test.mbt` | 19 | `markers.mbt`（1032）：PEP 508 环境标记文法与求值 |
| `toml_test.mbt` | 16 | `toml.mbt`（1580）：TOML 1.0 与规范重序列化 |
| `licenses_test.mbt` | 25 | `licenses.mbt`（460）：PEP 639 许可证表达式与许可证文件路径 |
| `metadata_test.mbt` | 47 | `metadata.mbt`（1378）：core metadata（PEP 566/621/639/643/685/753） |
| `index_test.mbt` | 52 | `index.mbt`（1251）：PEP 691 JSON、离线目录扫描、候选解析 |
| `pylock_test.mbt` | 32 | `pylock.mbt`（1280）：PEP 751 锁文件 |
| `audit_test.mbt` | 8 | `audit.mbt`（332）：跨制品审计（需求 → 元数据 → 索引 → 锁 → 目标环境） |
| `tags_test.mbt` | 17 | `tags.mbt`（448）：PEP 425 标签计算 |
| `upgrade_test.mbt` | 16 | `upgrade.mbt`（284）：升级短名单的六条规则顺序，以及「预发布策略只能经由区间起作用」 |
| `properties_test.mbt` | 4 | 跨模块性质：比较的反自反/反对称/传递性、规范化幂等、`filter` 的稳定性 |
| `regression_test.mbt` | 4 | 由历史缺陷触发的回归（§5） |

单元测试不写「输入输出对照表」了事，而是**断言错误码**：每一处拒绝都返回稳定码
（`VersionError::InvalidXxx(code, offset)`），测试直接断言 `code`，因此规则被改名或
被绕过时测试会报出来，而不是只报「某处失败了」。

### 2.2 差分实验（122 640 条记录）

`examples/diff`（2862 行）是确定性发射器：同一份输入在任何后端、任何时间输出
逐字节相同的语料。`tools/diff_packaging.py`（1700 行）把每条记录交给 CPython 的
`packaging` 独立重算并逐条比对。

| 记录类型 | 条数 | 对照的 API |
| --- | ---: | --- |
| `contains` | 60 870 | `SpecifierSet.contains` |
| `cmp` | 13 427 | `Version` 比较 |
| `parse` | 10 132 | `Version` |
| `marker_eval` | 8 520 | `Marker.evaluate(env)`（5 套固定环境） |
| `canon` | 6 159 | `canonicalize_name` / `canonicalize_version` |
| `file` | 4 950 | `parse_wheel_filename` / `parse_sdist_filename` |
| `req` | 4 662 | `packaging.requirements.Requirement` |
| `marker` | 4 575 | `packaging.markers.Marker` |
| `license` | 4 086 | `canonicalize_license_expression` |
| `spec` | 2 491 | `SpecifierSet` |
| `filter` | 993 | `SpecifierSet.filter` |
| `meta_values` | 915 | `Metadata.from_email` 的**逐值**结果 |
| `meta` | 285 | `Metadata.from_email(data, validate=True)` |
| `pylock` | 215 | PEP 751 的第二份读法（无现成实现） |
| `index` | 118 | PEP 691 规范（投影两处独立重算） |
| `toml` | 83 | `tomli 2.4.1` |
| `tag` | 62 | `packaging.tags` 的六个函数 |
| `upgrade` | 51 | 用 `packaging` 重写的升级短名单（同一组参数，含被弃原因） |
| `resolve` | 18 | 用 `packaging` 重写的候选选择与排序 |
| `meta_divergence` / `tag_divergence` / `index_dir` / `marker_env` / `order` / `index_divergence` / `pylock_divergence` | 7 / 6 / 5 / 5 / 3 / 1 / 1 | 声明分歧与输入记录（不是断言） |
| **合计** | **122 640** | — |

语料来源：`pypi` 47 677、`mutated` 34 397、`generated` 20 652、`curated` 19 567、
`curated_bad` 98、`pypi_index` 97、`pypi_lock` 95、`uv_lock` 6。

真实数据不是装饰：97 个 PyPI 包的 **3 000 个版本**、**500 条真实约束**、
**600 条真实 `Requires-Dist` 原文**、**900 个真实分发文件名**、
**239 份真实 `METADATA`**（真实 wheel 的 PEP 658 边上文件）、
**97 份真实 PEP 691 索引响应**、**6 份 `uv` 写出的真实 `pylock.toml`**。

### 2.3 规范对照（没有现成实现的那几类）

`packaging` 覆盖版本、约束、文件名、需求行、标记、许可证与核心元数据；
以下三类它不覆盖，因此对照物是**按规范正文另写的第二份读法**，并明确标注
「这一层抓不出两份读法同时读错同一段规范」：

- `pylock`：`tools/fetch_pylock_corpus.py`（1702 行）给出裁决 + 投影；
- `index` / `index_dir`：`tools/fetch_index_corpus.py`（441 行）；
- `tag`：`tools/fetch_tag_corpus.py`（518 行）——这一类特殊，`packaging.tags` 是
  纯函数，harness 在回放时用**同一组参数**调用参考实现，两侧比较有序标签表。

### 2.4 变异探针（43 处注入，全部检出）

`tools/mutation_probe.py`（749 行）向库源码注入 43 处**故意缺陷**（每次一处、
单点修改），重跑语料并断言 harness 报错。注入点覆盖 M0–M13 的行为：名称规范化、
标签排序与大小写、版本键、wheel/sdist 切分、local 段比较、标记规范化与词汇表、
依赖行校验、SPDX 大小写、TOML 内联表/多行字符串/整数宽度、预发布策略、
元数据名称与 `Keywords` 去空白、PEP 751 的六条规则、PEP 425 的四条规则、
升级短名单的预发布策略与同版本判断。

检出条数不是重点，重点是**每处注入都必须被检出**——任何一处「注入后语料仍然报 0
不一致」都说明那部分行为没有被任何记录钉住。当前 43/43。

探针还带两道防误用的闸门（见 §5.4）：工作树已被修改时拒绝运行；源码里已经存在
某处注入的痕迹时也拒绝运行并点名。

### 2.5 多版本漂移矩阵

同一份语料在四个 `packaging` 版本上回放，差异按原因分类而不是隐藏：

| packaging | 记录数 | 差异 | fatal | 主要成因 |
| --- | ---: | ---: | ---: | --- |
| 24.2 | 122 640 | 4 492 | 0 | 自动预发布准入 1 749、标记求值 1 998、标记文法 184、许可证 153、文件名 142、独占比较 209、标签生成 24、oracle 自身崩溃 28 |
| 25.0 | 122 640 | 2 754 | 0 | 同上，标记求值降到 357、标记文法 87 |
| 26.0 | 122 640 | 844 | 0 | 独占比较 209、文件名 142、许可证 66、标记求值 285、标记文法 87、标签生成 24、oracle 崩溃 27 |
| **26.3（目标）** | 122 640 | **0** | **0** | — |

差异全部对应上游**已发布的行为变更**（空约束的自动预发布准入、`<`/`>` 的区间
实现、`~=` 上界、26.3 的文件名验收与标记语法收紧、26.1 起的选择器 API、
26.3 起的纯 Python 标签 API），每类都在 `docs/experiment-results.md` §4 给了最小复现。
固定 26.3 是实测选定，不是随手写的。

### 2.6 四后端一致性

| 后端 | 记录数 | 字节数 | 摘要 |
| --- | ---: | ---: | --- |
| wasm | 122 641 | 12 431 239 | `c1d13895f753bc21` |
| wasm-gc | 122 641 | 12 431 239 | 同上（逐字节相同） |
| js | 122 641 | 12 431 239 | 同上（逐字节相同） |
| native | 122 641 | 12 431 239 | 同上（逐字节相同） |

四个场景示例的报告同样要求四后端逐字节一致：
`examples/metadata-check` md5 `2cedc437f5b3c11ec45d25ca7586fcc7`、
`examples/resolve` md5 `e58c1ff44ab61b0008d4bfa76f794680`、
`examples/audit` md5 `9d3cadf92d802ba26d5bf0d2b90c392e`、
`examples/upgrade-check` md5 `4339ad2e4afabe2d11c23f76665dd192`。
语料生成器重复运行也逐字节一致（js 两次输出与捕获文件 md5 均为
`4fda72d43a4eae8c8c8545e32c8e028d`）。

### 2.7 场景端到端

四个可运行示例把库的能力串成完整链路，各自有固定输入与固定输出：

1. `examples/metadata-check`（372 行）：四份真实 `METADATA` + 一份真实 `pylock.toml`
   + 目标环境 → 逐条判定与汇总（含「这份锁文件有几条是为另一个平台锁定的」）。
2. `examples/resolve`（570 行）：一份 PEP 691 索引响应 + 目标标签表 + 一个 wheelhouse
   目录 → yank 策略、每个被拒文件的首条失败规则、候选排序与最终选择。
3. `examples/audit`（36 行 + `audit.mbt` 332 行）：需求 + 真实 Flask 0.12.5 `METADATA`
   + 索引 + 锁文件 + CPython 3.11/Linux 目标 → `Ready` / `Blocked` / `NotRequired`
   与稳定问题码；输出中排除了一项 yanked 候选，并声明 sha256。
4. `examples/upgrade-check`（268 行 + `upgrade.mbt` 284 行）：当前版本 + 目标区间
   + 候选列表 + 目标解释器 → 升序短名单与每个被弃候选的原因码；报告末尾由库自己
   打印这一层**没有**检查什么（API 兼容、依赖可解、安全公告、构建与测试结果）。

### 2.8 fixture 自检

七份生成式 fixture（`pypi_corpus`、`toml_corpus`、`metadata_corpus`、`pylock_corpus`、
`index_corpus`、`tag_corpus`、`upgrade_corpus`）各自配一个生成器，生成器支持 `--check`：
重新生成到内存、按提交文件的格式过一遍 `moon fmt`、逐字节比对，且**无论成功失败都
把提交的文件恢复原样**。CI 每次运行 `pylock` / `tag` / `upgrade` 的完整 `--check`
与 `metadata` 的 `--check-cases`（元数据 fixture 的真实文档缓存不入库，因此 CI 只校验
可复现的那一半）。

---

## 3. 复现方式

```sh
# 1. 单元测试（四个后端）
moon check --target wasm-gc --deny-warn
moon test  --target wasm-gc --deny-warn      # → Total tests: 293, passed: 293, failed: 0.

# 2. 差分实验（需要 packaging==26.3 的 venv）
python -B tools/diff_packaging.py --oracle-version 26.3
# → OK: 122640 records agree with packaging 26.3

# 3. 四后端一致性 + 语料确定性
python -B tools/target_parity.py
moon run examples/diff --target js | md5sum   # 跑两次，逐字节相同

# 4. 多版本漂移矩阵
python -B tools/oracle_matrix.py --oracle <venv24.2>/bin/python ... 

# 5. 变异探针（工作树必须干净）
python -B tools/mutation_probe.py --oracle <venv26.3>/bin/python
# → OK: all 43 mutations were detected by the corpus

# 6. 场景示例
for t in wasm wasm-gc js native; do moon run examples/metadata-check --target $t; done
for t in wasm wasm-gc js native; do moon run examples/resolve        --target $t; done
for t in wasm wasm-gc js native; do moon run examples/audit          --target $t; done
for t in wasm wasm-gc js native; do moon run examples/upgrade-check  --target $t; done

# 7. fixture 与生成器一致
python -B tools/fetch_pylock_corpus.py --check
python -B tools/fetch_tag_corpus.py    --check
python -B tools/fetch_upgrade_corpus.py --check
python -B tools/fetch_metadata_corpus.py --check-cases

# 8. 源码口径（对外引用行数时用这个）
python -B tools/source_metrics.py
```

CI（GitHub Actions）在 `main` 的每个提交上跑两件事：四后端 verify 矩阵
（`fmt/check/build/test/run`）与独立的 differential 作业（固定
`packaging==26.3` 与 `tomli==2.4.1` 并断言读取器版本）。当前 `main` 的最近提交
均为 success。

---

## 4. 覆盖矩阵（按规范）

| 规范 | 库内实现 | 单元测试 | 差分记录 |
| --- | --- | --- | --- |
| PEP 440 版本与版本约束 | `version.mbt` / `specifier.mbt` | 15 + 11 块 | `parse` / `cmp` / `spec` / `contains` / `filter` / `order` 共 91 913 条 |
| PEP 503 名称规范化 | `utils.mbt` | 14 块 | `canon` 6 159 条 |
| PEP 425 平台标签 | `tags.mbt` + `parse_wheel_filename` | 17 块 | `tag` 62 条 + `file` 4 950 条 |
| PEP 427/625 分发文件名 | `utils.mbt` | 同上 | `file` 4 950 条 |
| PEP 508 需求行与环境标记 | `requirements.mbt` / `markers.mbt` | 13 + 19 块 | `req` 4 662、`marker` 4 575、`marker_eval` 8 520 条 |
| PEP 566/621/639/643/685/753 核心元数据 | `metadata.mbt` | 47 块 | `meta` 285、`meta_values` 915 条（含 239 份真实文档） |
| PEP 639 许可证表达式 | `licenses.mbt` | 25 块 | `license` 4 086 条 |
| TOML 1.0 | `toml.mbt` | 16 块 | `toml` 83 条（对照 `tomli`） |
| PEP 691 索引响应 | `index.mbt` | 52 块 | `index` 118 条（含 97 份真实响应） |
| PEP 700 索引版本列表 | `index.mbt` | 同上 | 同上 |
| PEP 592 yank 策略 | `index.mbt`（只提供状态，策略在调用方） | 同上 | `resolve` 18 条 + 场景 2 |
| PEP 751 锁文件 | `pylock.mbt` | 32 块 | `pylock` 215 条（含 6 份真实 `uv` 输出） |
| 跨制品审计 | `audit.mbt` | 8 块 | `resolve` 18 条 + 场景「跨制品审计」 |
| 升级候选评估 | `upgrade.mbt` | 16 块 | `upgrade` 51 条 + 场景「升级候选评估」 |

---

## 5. 测试查出的缺陷（这是测试是否有效的直接证据）

### 5.1 扩宽差分实验时查出的 3 处库缺陷（659 条不一致）

语料从 2 050 项扩到 43 573 项时 harness 报出 659 条不一致，分 5 组，其中 3 处是库错：

| 缺陷 | 不一致条数 | 原因 |
| --- | ---: | --- |
| 后缀分隔符文法 | 424 + 110 | 只接受 `.post1` 一类拼写，不接受 `1.0post1`、`1.0-post1`、`1.0a1post2dev3`、`1.0a1-5` |
| 文本 local 段比较 | 1 | MoonBit 的 `String` 比较先比长度，把 `0+x` 排在 `0.0+a1` 前；PEP 440 按字节序 |
| 约束操作数字符限制 | 97 + 23 | 允许 `!=2.0 .*`、`>=1.0 <=2.0` 这类含空白的操作数，也允许 `===` 里禁止的空格/`;`/`)` |

三处修复后同一份语料 0 不一致，并各补了回归测试（`regression_test.mbt` 与
`specifier_test.mbt` 中对应的块）。

### 5.2 逐值对照查出的 3 处元数据缺陷

原先的 `meta` 记录只比对「接受/拒绝」与「重排往返」，问不出「值对不对」——
参考实现读入时就去空白、规范化名称，库写错的拼写恰好被**用来检查它的那一步**抹平。
新增 `meta_values`（逐值一条记录）后立刻查出三处：

| 缺陷 | 现象 | 原因 |
| --- | --- | --- |
| `Name` 可以下划线结尾 | 库接受 `Name: demo_`，`packaging` 报 `InvalidMetadata(field "name")` | 收尾判断写成 `is_ascii_alphanumeric(c) \|\| c == '_'`；`_` 只在名称**中间**合法 |
| `Provides-Extra` 同上 | 库接受 `Provides-Extra: demo_` | 同一个判断函数 |
| `Keywords` 分段未按 Python 去空白 | `a,<VT>b` 在库里得到 `["a", "<VT>b"]`，参考得到 `["a", "b"]` | 分段用 RFC 5322 的 WSP 去空白，而参考用 `str.strip()` |

三处都**反转**（而不是删除）原先记录旧行为的断言，因此修复本身也被断言。

### 5.3 差分协议本身的转义漏洞

写 `Keywords` 垂直制表符样例时发现：发射器只转义反斜杠、制表符、LF、CR，一个
**原始垂直制表符**对「按行读语料」的工具是记录分隔符，对 MoonBit 词法器更是换行
——记录被劈成两半。已改为把**所有控制字符**转义成 `\u{..}`，harness 侧认识该转义，
两个 fixture 生成器写文档字面量时也转义整类字符。**没有这一步，那两条 `Keywords`
样例根本无法表达**。

### 5.4 测试基础设施自身的 4 处缺陷

| 缺陷 | 现象 | 修复 |
| --- | --- | --- |
| fixture 被手写 stub 覆盖 | 一次同步把 34 行的手写桩推上服务器，覆盖了生成的 805 行 fixture，还被提交进 `37b672f`；语料照跑、照样报 0 不一致，只是**对照的是错的输入** | 重新生成，并给所有生成器加 `--check`，CI 每次运行 |
| `--check` 会把被检查的文件改掉 | 在没有 `moon` 的早退路径上，`--check` 已经把文件写成新内容 | `try/finally` 恢复原文件 |
| 变异探针残留注入 | 被 SIGKILL 的运行无法执行 `finally`，注入的缺陷留在源码里；更糟的是残留如果**挨着另一处注入的锚点**，探针会照跑并让所有计数虚高（实测一处计数从 105 变成 937） | 新加：源码里已存在某处注入的痕迹时**拒绝运行并点名**；工作树已被修改时也拒绝运行（`--allow-dirty` 需显式打开） |
| 漂移矩阵读到陈旧报告 | `oracle_matrix.py` 在跑某个 oracle 前不删除旧报告，子进程早退时会把**上一次运行的数字**当成这一次的结果显示 | 每个子运行前先删除报告文件 |

### 5.5 语料漏洞：一处「看起来钉住了、其实什么都没钉」的样例

收敛 PEP 751 分歧时，变异探针第一次跑就报 `pylock-ignores-source-exclusivity`
**NOT DETECTED**。追下去发现是**语料**的问题：钉住「来源互斥」的那份样例同时带了
`version`，于是把互斥检查关掉之后文档仍然被**版本规则**拒掉——它等于什么都没钉住。
补了 4 条不带 `version` 的互斥样例（每对成员一条）后，同一处注入立刻被检出。

**一条样例只有在它除此之外完全合法时，才钉得住那条规则。**

### 5.6 语料覆盖不到的地方：wheel 标签大小写

写 PEP 425 标签语料时又查出同类问题，这次是库错、语料漏：
`packaging` 的 `Tag` 在构造时把解释器、ABI、平台三段全部小写，而库的
`parse_tag_set` 直接拼接原文。差分实验此前一次都没报，因为语料里**每一个**文件名
（手工的与真实的）都写小写——**两侧对同一个拼写都不产生输入时，语料无法就那个拼写
表态**。补了 5 个大小写混写的文件名后语料涨到 122 521 条，并加了
`wheel-tag-case-not-normalized` 探针：修复前那处注入是**绿的**。

### 5.7 PEP 751 的六处放宽（规范正文逐条对照后收敛）

库最初对 PEP 751 有 7 处「声明分歧」。把规范正文的 `Required?` 行逐条调出来看，
其中 6 处是库**比规范松**，即缺陷而非设计选择，已全部收紧（`created-by` 必填、
文件记录必须有非空 `hashes`、`upload-time` 必须 UTC、源树旁禁止 `version`、
文件列表条目不再强制 `version`），并各补一条「除此之外完全合法」的普通样例钉住；
保留的 1 条是库有意比规范**严**（未实现的次版本 `lock-version` 拒绝而非警告，
因为本库没有警告通道）。`pylock_cases/divergences.txt` 从 7 行降到 1 行。

---

## 6. 测试没有证明什么

写清楚「没证明什么」和写清楚「证明了什么」同样重要：

- **不证明与规范完全一致**：第 2 层的参照物是另一份实现（`packaging`）而不是规范。
- **不覆盖全部现实输入**：122 640 条是一次抽样，PyPI 的真实版本远多于 3 000 个；
  真实 `METADATA` 只覆盖 239 份（有 PEP 658 边上文件的那些），且丢弃了 12 000 字符
  以上的文档；真实索引响应超过 20 个文件或 40 个版本的部分被截断（fixture 里写明）。
- **`pylock` 抓不出「两份读法同时读错同一段规范」**：`packaging` 没有
  `pylock.toml` 读取实现，所以那一层对照的是本仓库按规范另写的读法。
  6 份 `uv` 写出的真实锁文件补的是**输入的独立性**（文档不是本仓库生成的），
  但 `uv` 只写不读、不给出裁决，因此**没有**补上第二份读法。
- **不覆盖宿主探测**：标签的展开与排序已实现并逐条对照 `packaging.tags`，但
  `sys_tags()` / `platform_tags()` 要读 `sys.version_info`、`sysconfig`、
  `EXT_SUFFIX` 与运行中的 libc，这些输入只由调用方提供；三条「参考实现会去读宿主」
  的输入被登记为声明分歧（`tag_divergence`），而不是把宿主机器的值写进 fixture。
- **标记求值只对照了 5 套环境**；`packaging` 在缺键时会回落到宿主进程的真实环境值，
  本库拒绝这个回落（不读运行时环境），因此「缺键」这一类行为是设计差异而非等价性结论。
- **旧版 `packaging` 的差异被归类为上游行为变更**，这依赖「库对齐 26.3」这一前提；
  换目标版本需要重新评估（`tools/oracle_matrix.py` 就是为此准备的）。
- **不做依赖求解、下载与安装**，也不评估升级的安全性——超出本库范围。升级短名单
  同样只回答版本问题：`upgrade` 那 51 条记录证明的是两侧对「谁落在区间内、谁被哪条
  规则拦下」给出同一答案，不证明短名单上的版本可以安全升级。
- **`upgrade` 的这一层对照覆盖了策略与区间，但没有覆盖"策略该不该起作用"**：没有
  目标区间时显式禁用预发布不起作用，这是与 `SpecifierSet::filter` 一致的选择，也
  就是说是两个实现共同的选择，不是规范明文。

---

## 7. 结论

| 检查项 | 结果 |
| --- | --- |
| 单元测试 | 293 个测试块 × 4 后端 = 1 172 次全通过 |
| 差分实验（`packaging==26.3`） | 122 640 条记录，**0 不一致** |
| 变异探针 | 43 处注入缺陷，**43/43 全部检出** |
| 四后端一致性 | 语料与 4 个场景报告逐字节一致 |
| 多版本漂移 | 24.2 → 4 492、25.0 → 2 754、26.0 → 844、26.3 → **0** |
| fixture 自检 | 全部 fixture 与当前生成器输出一致 |
| 查出的库缺陷 | 13 处，全部修复并有回归测试或探针守 |
| CI | `main` 最近提交均为 success（四后端矩阵 + differential 作业） |

这套测试的价值不在于那 293 个块或 122 640 条数字，而在于**它抓到过东西**：
13 处库的真实缺陷（3 处文法/比较、3 处逐值元数据、1 处标签大小写、6 处 PEP 751
放宽）、4 处测试基础设施缺陷、1 处语料漏洞，以及 1 处「库错而语料漏」的覆盖盲区。
每抓到一个，都会在同一次改动里补上**能再抓到它的**那一层——这也是为什么
「0 不一致」在这里可以和「对照能失败」一起说。

---

## 8. M14 补记：锁定候选与双包审计（2026-09-20）

上述 M13 数字保留为历史基线。本轮修正单包审计：先按锁定版本选文件，再比较所选
文件名和索引、锁文件双方的 sha256 声明；新增多包共用锁文件的 `audit_bundle`。

本地复核：300 个测试块在 wasm、wasm-gc、js、native **各 300/300 通过**；
`examples/bundle-audit` 在四后端均得到两包 `Ready`，分别选中真实 PyPI 索引中的
Flask 0.12.5 与 Jinja2 2.10.1 wheel。负向测试覆盖摘要漂移、文件缺失、重复输入
与锁条目未审计。固定 `packaging==26.3` 的 122,640 条差分记录仍为 0 不一致。
生产代码与测试的当前口径分别为 9,984 与 7,460 行；生成语料不计入生产源码。
新提交的线上 CI 结论应以对应 GitHub Actions 运行记录为准，不能引用本报告旧基线代替。
