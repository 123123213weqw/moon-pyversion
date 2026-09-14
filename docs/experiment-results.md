# 差分实验：结果

复现命令与设计见 [experiment.md](experiment.md)。本文只记录实际跑出来的数字，
全部来自本仓库当前提交，`moon` 0.1.20260904（moonc v0.10.12）、CPython 3.10.12；
测试与语料在四个后端各跑一遍，oracle 侧用 `packaging` 26.3。

## 1. 语料规模

| 来源 | parse | spec | cmp | contains | filter | order | canon | file | req | marker | marker_eval | toml | license | meta |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| curated | 81 | 47 | 6561 | 11421 | 141 | 1 | 57 | 45 | 62 | 104 | 520 | 83 | 86 | 42 |
| generated | 4000 | 700 | 3000 | 12600 | 351 | 1 | — | — | — | — | — | — | — | — |
| mutated | 3051 | 1244 | — | — | — | — | 6102 | 4000 | 4000 | 4000 | 8000 | — | 4000 | — |
| pypi | 3000 | 500 | 3866 | 36849 | 501 | 1 | — | 900 | 600 | 471 | — | — | — | 239 |
| **合计** | **10132** | **2491** | **13427** | **60870** | **993** | **3** | **6159** | **4945** | **4662** | **4575** | **8520** | **83** | **4086** | **281** |

另有 5 条 `marker_env`（环境定义，不是断言）与 7 条 `meta_divergence`
（声明分歧，不是断言），合计 **121 381 条记录 / 121 382 行语料**，其中
**61 863** 条带显式预发布模式（`auto`/`any`/`none`）。

- 来源分布：curated 19 296、curated_bad 12、generated 20 652、mutated 34 397、
  pypi 46 927、pypi_index 97。
- oracle 侧接受的**互不相同**的版本字符串 11 035 个、约束集合 1 595 个。
- pypi 来源：97 个包的 PyPI 元数据，**3000 个版本、500 条约束、600 条真实
  `Requires-Dist` 原文、900 个真实分发文件名**，详见
  `fixtures/pypi_corpus.json`（抓取时 0 个包失败）。
- `canon` / `file` 是 M1（`utils.mbt`）新增的两类记录：名称与版本键规范化、
  分发文件名解析。其中 `file` 的状态分布为 wheel 成功 2904 / 失败 919、
  sdist 成功 216 / 失败 172、其他 734，不是只测成功路径。
- M2–M5 又加了几类：`req`（PEP 508 依赖行）、`marker` + `marker_eval`（标记
  文法与求值）、`toml`（TOML 1.0 文档）、`license`（PEP 639 表达式）。`marker_eval`
  是在 5 套完整环境上各评一次，因此条数明显多于 `marker`。
- M7 加 `index`（PEP 691 映射）、`index_dir`（离线目录扫描）与 `resolve`
  （候选解析）：21 个手工文档 + **97 份真实 PEP 691 索引响应**（从公共索引的
  JSON API 抓取；超过 20 个文件或 40 个版本的响应被截到该长度，fixture 里写明）。
- M6 加 `meta`：**42 条手工规则样例 + 239 份真实 `METADATA`**，后者是从 PyPI
  上真实 wheel 的 PEP 658 `.metadata` 边上文件抓下来的（`fixtures/metadata_cache/`
  是原始下载缓存，不入库；`fixtures/metadata_corpus.json` 记录每份文档的大小与
  参考实现的裁决）。下载 593 份、入库 239 份，其余按"超过 12 000 字符"丢弃
  （体积计入语料，一份 200 kB 的描述会压过整个语料），丢弃数量写在 provenance
  里而不是静默省略。

## 2. 与目标 oracle（packaging 26.3）的一致性

```
oracle: packaging 26.3 (python 3.10.12), library targets packaging 26.3
toml reference reader: tomli
records: 121381 (61863 with a prerelease mode)
mismatches per source, kind and mode:
  none
OK: 121381 records agree with packaging 26.3
```

退出码 0。**0 不一致**。

## 3. 四后端一致性

```
reference: wasm
target      records      bytes  seconds  digest
wasm         121382   11735355     4.91  ee988e0c60474e2f
wasm-gc      121382   11735355     3.75  ee988e0c60474e2f identical
js           121382   11735355     3.58  ee988e0c60474e2f identical
native       121382   11735355     4.50  ee988e0c60474e2f identical
```

语料生成器在四个后端输出逐字节相同（sha256 前 16 位一致）。重复运行的
js 输出与捕获文件 md5 一致（`a8fdf4fe590b3e1ae11a0aabf43b4e48`），即生成
过程可重复。

## 4. 多 oracle 漂移矩阵

同一份语料在不同 `packaging` 版本下回放（`tools/oracle_matrix.py`）：

| packaging | records | differences | fatal | causes |
| --- | ---: | ---: | ---: | --- |
| 24.2 | 121381 | 4474 | 0 | auto-prerelease-admission x1749, compatible-release-range x3, exclusive-ordered-comparison x209, filename-grammar x148, index-scan x1, license-expression x153, marker-evaluation x1998, marker-grammar x184, metadata-rules x1, oracle-crash x28 |
| 25.0 | 121381 | 2736 | 0 | auto-prerelease-admission x1749, compatible-release-range x3, exclusive-ordered-comparison x209, filename-grammar x148, index-scan x1, license-expression x153, marker-evaluation x357, marker-grammar x87, metadata-rules x1, oracle-crash x28 |
| 26.0 | 121381 | 826 | 0 | compatible-release-range x3, exclusive-ordered-comparison x209, filename-grammar x148, index-scan x1, license-expression x66, marker-evaluation x285, marker-grammar x87, oracle-crash x27 |
| **26.3（目标版本）** | 121381 | **0** | **0** | — |

四个 oracle 都能回放全部 121 381 条记录，fatal 都是 0（旧版本按 `--tolerate-drift`
记为容忍漂移）。`index-scan` 那 1 条与 `filename-grammar` 是同一处上游变更：目录清单里有
`-1.0-py3-none-any.whl`（项目名为空），26.3 起拒绝，旧版本接受，所以同一次扫描
在旧 oracle 上少识别出一个文件。`oracle-crash` 是新增的
一类原因：27–28 条记录上**旧版本自己抛异常**
（把非法的转义序列交给 `ast.parse`，抛 `SyntaxError`，而 26.3 会抛
`InvalidMarker`）。这类记录以前会让整轮回放中断、连报告都写不出来——现在被
当成"参考实现在这条输入上失败"，按差异统计并给出原因，而不是让工具崩掉。


差异全部落在三个已发布的上游行为变更上，各给一个最小复现：

| 现象 | 旧版本结果 | 26.3 结果 | 记录数 |
| --- | --- | --- | ---: |
| `SpecifierSet("").contains(Version("1.0a1"))`（空约束，自动策略） | ≤25.0 为 `False`；26.0 起 `True` | `True` | 1749（仅 ≤25.0） |
| `SpecifierSet(">1.0a1").contains(Version("1.0.post1"), prereleases=True)` | ≤26.0 为 `False`（旧实现在 `_compare_greater_than` 里按 base version 排除 post/local） | `True` | 209（≤26.0） |
| `SpecifierSet("<1.0.post1").contains(Version("1.0a1"), prereleases=True)` | ≤26.0 为 `False` | `True` | 同上 |
| `SpecifierSet("~=0.5.preview").contains(Version("0.12"), prereleases=True)` | ≤26.2 为 `False`（上界按 `1.dev0` 算） | `True` | 3 |
| `parse_wheel_filename("-1.0-py3-none-any.whl")` / `parse_sdist_filename("-1.0.tar.gz")` | ≤26.0 **接受**（项目名可为空） | 拒绝 | 148 |
| `parse_wheel_filename("foo-1.0-2py-none-any.whl")` / `...-py3--any...` | ≤26.0 **接受**（不校验解释器标识符与空组件） | 拒绝 | 同上 |

分类不是猜的：`auto-prerelease-admission` 的判定方式是"把 prereleases 强制打开后
旧 oracle 就与库一致"，因此这一类差异**只**关于自动策略；其余按约束文本归入
`<`/`>` 与 `~=` 两组（`tools/diff_packaging.py::classify_difference`）。

结论：**oracle 版本必须固定**。库对齐 26.3，并把旧版本的差异按原因分类单独
统计，而不是隐藏、跳过或改写断言；目标版本仍然是硬性 0 差异。

## 5. 这次扩宽实验查出的缺陷

语料从 2050 项扩大到 43 573 项（尚未装入 PyPI 语料）时，harness 报出
**659 条不一致**，分成 5 组；三处是库的真实缺陷，已修复并补了回归测试：

| 缺陷 | 修复前的不一致 | 原因 |
| --- | ---: | --- |
| 后缀分隔符文法 | `generated/parse` 424 + `mutated/parse` 110 | 只接受 `.post1` 一类拼写，不接受 `1.0post1`、`1.0-post1`、`1.0a1post2dev3`、`1.0a1-5` |
| 文本 local 段比较 | `generated/order` 1 | MoonBit 的 `String` 比较先比长度，把 `0+x` 排在 `0.0+a1` 之前；PEP 440 按字节序比较 |
| 约束操作数字符限制 | `generated/spec` 97 + `mutated/spec` 23 | 允许了 `!=2.0 .*`、`>=1.0 <=2.0` 这类含空白的操作数，也允许了 `===` 里 packaging 禁止的空格/`;`/`)` |

修复后同一份语料 0 不一致；三处都写进了
`version_test.mbt` / `specifier_test.mbt`（见 "separators around suffix
labels…"、"textual local segments order lexically…"、"whitespace is allowed
around a specifier…"、"arbitrary equality keeps packaging's operand
restrictions"）。

## 5.5 语料是否有牙：变异探针

0 不一致只有在"对照能失败"的前提下才有意义。`tools/mutation_probe.py` 向库
里注入 25 处**故意缺陷**（涵盖 M0–M7 的行为），重跑语料并断言 harness 报错：

| 注入的缺陷 | 检出条数 |
| --- | ---: |
| `canonicalize_name` 丢掉尾部/首部分隔符 | 116 |
| 标签排序退回默认 `String` 比较（按长度） | 214 |
| 版本键形式保留尾部零 | 401 |
| wheel 项目名不做规范化 | 395 |
| sdist 从第一个连字符切分 | 35 |
| local 文本段按长度比较 | 1 |
| 标记环境里的 `extra` 不做规范化 | 6 |
| 标记环境里的集合成员不做规范化 | 6 |
| `in` 的左右操作数调换 | 87 |
| 标记词汇表漏掉 `extras` | 258 |
| 依赖行里的标记不做校验 | 906 |
| SPDX 标识符区分大小写 | 830 |
| 内联表允许换行（TOML 1.1 行为） | 1 |
| 多行字符串吞掉首字符 | 3 |
| TOML 整数退化为 32 位 | 1 |
| 预发布策略恒为允许 | 2038 |
| `Metadata-Version` 门槛失效（未知字段与未知版本被放行） | 1 |
| `Requires-Dist` 的值不再解析 | 4 |
| PEP 639 的 `License-Expression` 与 `License` 冲突被放行 | 1 |
| PEP 639 的 `License-Expression` 与 `License ::` 分类器冲突被放行 | 1 |
| 重复的 JSON 成员名被接受（真实分歧消失） | 1 |
| 目录扫描退回默认 `String` 顺序（按长度） | 1 |
| 解析器忽略 PEP 425 标签 | 3 |
| 解析器忽略 `Requires-Python` | 10 |
| 解析器忽略预发布策略 | 12 |

25/25 全部检出。两个 TOML 探针各只检出 1 条，是**故意**的：它们的现象只在
单个语料样例上出现，如果未来那条样例被改坏，检出数会掉到 0，探针就会失败。

两条 `License-Expression` 冲突探针各只检出 1 条，同样是因为只有一个语料样例
能触发它；如果那条样例被改坏，检出数会掉到 0，探针就会失败。

`Author-email` 的两处行为（空值等价于缺席、解析失败只报告不致命）**没有**放进
这份探针：参考实现根本不解析这个字段，语料看不出差别，它们由单元测试覆盖。
这是刻意的取舍，写在这里以免被误读成"已经全覆盖"。

其中"内联表允许换行"这条探针还兼任**分歧方向**的守卫：`94_err_inline_newline`
是登记在 `toml_cases/leniencies.txt` 里的放宽项，库必须拒绝它。注入缺陷后
库会接受，生成器把状态从 `lenient` 改成 `lenient-drift`，harness 立刻报错
——也就是说"库永远不能变得和参考实现一样松"这件事同样有牙。

## 6. 测试与后端验证

| 检查 | 结果 |
| --- | --- |
| `moon fmt --check` | 通过 |
| `moon check/build/test --deny-warn`（wasm / wasm-gc / js / native） | 全部通过，每个后端 **219 个测试块全部通过**（合计 876） |
| `moon run examples/basic`（四后端） | 通过 |
| `moon run examples/diff`（四后端） | 121 382 行语料，四端字节一致 |

## 6.5 各阶段新增能力的覆盖

每一阶段都不是"新写一套验证"，而是**只增加记录类型**，被测代码换、验证方法
不换。到 M7 为止的记录构成（全部对 `packaging` 26.3，**0 不一致**，合计 121 381）：

| 记录类型 | 条数 | 对照的 packaging API | 来源 |
| --- | ---: | --- | --- |
| `contains` | 60 870 | `SpecifierSet.contains` | curated + generated + pypi（3 种预发布模式） |
| `cmp` | 13 427 | `Version` 比较 | curated + generated + pypi |
| `parse` | 10 132 | `Version` | curated + generated + mutated + pypi |
| `marker_eval` | 8520 | `Marker.evaluate(env)` | curated + mutated × 5 套环境 |
| `canon` | 6159 | `canonicalize_name` / `canonicalize_version` | curated + mutated |
| `file` | 4945 | `parse_wheel_filename` / `parse_sdist_filename` | curated + mutated + pypi |
| `req` | 4662 | `packaging.requirements.Requirement` | curated + mutated + pypi（600 条真实 `Requires-Dist`） |
| `marker` | 4575 | `packaging.markers.Marker` | curated + mutated + 471 条真实标记 |
| `license` | 4086 | `packaging.licenses.canonicalize_license_expression` | curated + mutated |
| `spec` | 2491 | `SpecifierSet` | curated + generated + mutated + pypi |
| `filter` | 993 | `SpecifierSet.filter` | curated + generated + pypi |
| `toml` | 83 | 参考实现 `tomli`（接受/拒绝 + 重序列化） | 83 个 TOML 文档 |
| `meta` | 281 | `Metadata.from_email(data, validate=True)` | 42 条手工规则样例 + 239 份真实 PyPI `METADATA` |
| `index` | 118 | 规范本身（写成一处投影，Python 侧独立重算） | 21 条手工文档 + 97 份真实 PEP 691 响应 |
| `index_dir` | 5 | 规范本身（`parse_wheel_filename` / `parse_sdist_filename` + 排序规则） | 5 个目录清单 |
| `resolve` | 18 | 用 `packaging` 重写的候选选择与排序 | 18 组（需求 × 标签 × 解释器 × 预发布策略） |
| `order` | 3 | `Version` 全序 | curated + generated + pypi |
| `marker_env` | 5 | —（环境定义，非断言） | 5 套完整环境 |
| `meta_divergence` | 7 | —（声明分歧，非断言） | curated |
| `index_divergence` | 1 | —（声明分歧，非断言） | curated |

TOML 的对照方式与其他记录不同，值得单独说明：参考实现给出"接受/拒绝"的裁决，
库另外给出自己的规范重序列化文本，harness 把这段文本用参考实现**重新解析**
并与原文解析结果逐值比较。一条记录同时验证文法、取值和往返一致性。

83 个样例里参考实现接受 50 个（库接受 46 个）／拒绝 33 个，双方在这 33 个上
完全一致。剩下 4 个是参考实现的放宽（内联表换行、内联表尾随逗号、`\xHH`
转义、超 64 位整数），库按 TOML 1.0 拒绝。这 4 条在
`toml_cases/leniencies.txt` 中显式登记，记录状态是 `lenient`，harness
断言"参考实现接受"且"库拒绝"这两个方向同时成立——**分歧被断言而不是被容忍**；
如果库哪天变得同样宽松，生成器改发 `lenient-drift`，harness 同样报错。

"参考实现"是谁必须写清楚：fixture 的裁决来自 **`tomli` 2.4.1**，生成时校验
`leniencies.txt` 里的每一条都真的被它接受；harness 也优先用 `tomli`，找不到
时回落到标准库的 `tomllib`，并把实际使用的读取器写进报告（`toml_reader` 字段）
和终端输出。两者对同一份样例的裁决在 80 个 TOML 1.0 文档上一致，只在上面
那 3 个放宽项上不同（标准库更严格）。无论用哪一个，"双方都拒绝"都算一致、
"一方接受一方拒绝"都算不一致，因此这条对照不会因为读取器不同而失效——
严格读取器的回退路径在 CI 的 Python 3.13 上实测过。

### 6.6 核心元数据（`meta`）的对照方式

`METADATA` / `PKG-INFO` 没有机器可读的 schema，参考实现是
`packaging.metadata.Metadata.from_email(data, validate=True)`。一条 `meta` 记录
的比对规则是：

- 双方裁决不同 → 不一致。两边都拒绝时**不比较错误种类**：规范没有 schema，
  两份实现对同一条规则给出的名字本来就不同（`'name' is a required field`
  对 `NAME_REQUIRED`）。
- 双方都接受 → 再把库自己的规范重排文本交给参考实现重新解析，比较一份**取值
  投影**（`Metadata-Version`、规范化后的 `Name`、`Version`、`Requires-Python`、
  排序后的 `Requires-Dist` / `Classifier` / `Provides-Extra`、
  `Description-Content-Type`、`Summary`、`License-Expression`、`Project-URL`、
  `Author-email` / `Maintainer-email`）。投影两侧都来自参考实现的解析，因此一条
  记录同时验证规则、取值与往返一致性。

**声明分歧**（`meta_divergence` 记录，7 条）是库故意与参考实现不同的地方，逐条
写清方向，并且在两个方向上都被断言：库必须给出与参考实现**相反**的答案，且参考
实现必须真的按声明那样回答（生成 fixture 时校验一次，harness 每轮回放时再校验
一次）。库哪天变得和参考实现一样松或一样严，记录就会变成普通不一致：

| 样例 | 参考实现 | 本库 | 原因 |
| --- | --- | --- | --- |
| `04_folded_summary` | 拒绝 | 接受 | 参考实现用 `compat32` 策略保留 RFC 5322 折行，库先展开折行（2.2.3）再看单行规则 |
| `06_metadata_25` | 接受 | 拒绝 | 参考实现支持 2.5；库实现到 2.4，声明未知版本的文档直接拒绝 |
| `09_license_expression_conflict` | 接受 | 拒绝 | PEP 639 禁止 `License-Expression` 与 `License`/`License ::` 并存，库执行该规则；参考实现 26.3 未实现 |
| `41_license_and_expression` | 接受 | 拒绝 | 同上，只涉及自由文本 `License` 字段 |
| `42_license_classifier_conflict` | 接受 | 拒绝 | 同上，只涉及 `License ::` 分类器 |
| `10_description_content_type_variant` | 拒绝 | 接受 | 参考实现把该字段限定为三个取值 + UTF-8；库接受任何形式良好的 `type/subtype` 加参数 |
| `31_folded_requires_dist` | 拒绝 | 接受 | 折行是参考实现拿去校验的值的一部分，库先展开表头再解析约束 |

另外两条已知差异不计入上面这张表，因为它们不影响裁决：`Author-email` /
`Maintainer-email` 在库里会被解析成 `(name, address)` 列表（参考实现原样存放），
解析失败只进 `diagnostics` 而不让文档失败。这条放宽是**实测驱动**的：239 份真实
文档里有 5 份（`kubernetes-10.0.0/10.0.1/10.1.0` 的 `Author-email: ` 与
`torch-1.0.0` 的 `Author-email: UNKNOWN`）会被更严的版本拒掉，而它们正是场景 1
要读的那种文档。

## 6.7 场景 1 的端到端输出

`examples/metadata-check` 把上面这些能力串成一个可运行产物：读真实 `METADATA`
（取自语料），对锁表与固定环境逐条判定，输出 `ok` / `OUT OF RANGE` /
`not applicable` / `not locked` / `UNPARSABLE` 与汇总。四份真实文档各自的用法：

```
== flask-0.12.5
   requires-python: (none)
   note: deprecated: Home-page is superseded by Project-URL
   note: classifier-not-current: License :: OSI Approved :: BSD License
   note: description-content-type-missing
   OUT OF RANGE  werkzeug: locked 2.0.0, needs <1.0,>=0.7
   ok            jinja2 3.1.4 >=2.4
   -> 4/4 lines parsed, 1 problem(s)
== alembic-1.5.8
   requires-python: !=3.0.*,!=3.1.*,!=3.2.*,!=3.3.*,!=3.4.*,!=3.5.*,>=2.7 -> 3.11.9 is allowed
   -> 4/4 lines parsed, 0 problem(s)
== requests-2.24.0
   INVALID METADATA: METADATA_VERSION_INVALID at 0
== kubernetes-10.0.0
   not applicable ipaddress
   not applicable adal
   -> 12/12 lines parsed, 0 problem(s)
```

`flask-0.12.5` 那条越界是**真实冲突**（该版本确实要求
`werkzeug<1.0,>=0.7`，而锁里是 2.0.0）；`requests-2.24.0` 声明
`Metadata-Version: 2.0`，这不是核心元数据规范定义过的版本，库与参考实现都拒绝
——真实数据上跑出了失败路径，而不是只跑通路径。四个后端的输出逐字节一致
（四后端 md5 一致：`1834d5459527`）。

输入是编译进去的：库只依赖 `moonbitlang/core`，core 没有文件系统包，示例因此
不从磁盘读文件（把常量换成文件或网络响应即可）。这一点在示例的注释里写明，不
含糊。

## 7. 吞吐（`examples/bench`，本机墙钟，非跨语言基准）

| 操作 | js | native |
| --- | ---: | ---: |
| `Version::parse` / 规范化 | 1145 ns/op | 3530 ns/op |
| `Version::compare` | 76 ns/op | 332 ns/op |
| `SpecifierSet::contains` | 450 ns/op | 1495 ns/op |
| `SpecifierSet::filter`（600 候选 × 500 约束集） | 495 µs/op | 4.18 ms/op |

`filter` 的每一次调用都在 600 个候选上跑完整约束集，因此量级明显大于单次
`contains`；这组数字只用来发现数量级回归，不作为性能承诺。

## 8. 这次实验**没有**证明什么

- 不证明与 PEP 440 规范本身完全一致：oracle 是另一份实现，不是规范。
- 不证明覆盖全部现实输入：121 381 条是一次抽样，PyPI 的真实版本远多于 3000 个；
  真实 `METADATA` 只覆盖 239 份（有 PEP 658 边上文件的那些），且丢弃了 12 000
  字符以上的文档。
- 不覆盖平台兼容性标签的匹配与排序、不覆盖依赖求解与冲突回溯。
- TOML、许可证表达式与核心元数据的对照各用了一个参考实现（`tomli` 2.4.1、
  `packaging.licenses`、`packaging.metadata`），PEP 691 的对照则是"把规范写成
  一处投影、在两份实现里各算一遍"，四者都不是规范文本本身；TOML、元数据与索引的
  差异分别在 `toml_cases/leniencies.txt`、`metadata_cases/divergences.txt` 与
  `index_cases/divergences.txt` 中逐条登记。
- 标记求值只对照了 5 套环境；`packaging` 在缺键时会回落到**宿主进程**的真实
  环境值，本库拒绝这个回落（不读运行时环境），因此"缺键"这一类行为是
  设计上的差异而非等价性结论。
- 旧版 `packaging` 的差异被归类为上游行为变更，这依赖"库对齐 26.3"这一
  前提；换目标版本就需要重新评估，`tools/oracle_matrix.py` 就是为此准备的。
