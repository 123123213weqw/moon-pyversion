# 差分实验：结果

复现命令与设计见 [experiment.md](experiment.md)。本文只记录实际跑出来的数字，
全部来自本仓库当前提交，`moon` 0.1.20260904（moonc v0.10.12）、CPython 3.10.12；
测试与语料在四个后端各跑一遍，oracle 侧用 `packaging` 26.3。

## 1. 语料规模

| 来源 | parse | spec | cmp | contains | filter | order | canon | file | req | marker | marker_eval | toml | license | meta |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| curated | 81 | 47 | 6561 | 11421 | 141 | 1 | 57 | 50 | 62 | 104 | 520 | 83 | 86 | 42 |
| generated | 4000 | 700 | 3000 | 12600 | 351 | 1 | — | — | — | — | — | — | — | — |
| mutated | 3051 | 1244 | — | — | — | — | 6102 | 4000 | 4000 | 4000 | 8000 | — | 4000 | — |
| pypi | 3000 | 500 | 3866 | 36849 | 501 | 1 | — | 900 | 600 | 471 | — | — | — | 239 |
| **合计** | **10132** | **2491** | **13427** | **60870** | **993** | **3** | **6159** | **4950** | **4662** | **4575** | **8520** | **83** | **4086** | **285** |

M6 之后新增的几类记录不进上面这张表，因为它们与"版本/约束/文件名"的三条来源
轴不是同一个切分方式，单独列出：

| 来源 | meta_values | pylock | tag |
| --- | ---: | ---: | ---: |
| curated | 165 | 28 | 62 |
| curated_bad | — | 86 | — |
| pypi | 750 | — | — |
| pypi_lock | — | 95 | — |
| uv_lock | — | 6 | — |
| **合计** | **915** | **215** | **62** |

另有 5 条 `marker_env`（环境定义，不是断言）、7 条 `meta_divergence`、1 条
`index_divergence`、1 条 `pylock_divergence` 与 6 条 `tag_divergence`（都是声明
分歧，不是断言），合计 **122 589 条记录 / 122 590 行语料**，其中 **61 863** 条带显式预发布模式
（`auto`/`any`/`none`）。

- 来源分布：curated 19 567、curated_bad 98（其中 86 条是 pylock 的拒绝样例）、
  generated 20 652、mutated 34 397、pypi 47 677、pypi_index 97、pypi_lock 95、
  uv_lock 6。
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
- M6 加 `meta`：**46 条手工规则样例 + 239 份真实 `METADATA`**，后者是从 PyPI
  上真实 wheel 的 PEP 658 `.metadata` 边上文件抓下来的（`fixtures/metadata_cache/`
  是原始下载缓存，不入库；`fixtures/metadata_corpus.json` 记录每份文档的大小与
  参考实现的裁决）。下载 593 份、入库 239 份，其余按"超过 12 000 字符"丢弃
  （体积计入语料，一份 200 kB 的描述会压过整个语料），丢弃数量写在 provenance
  里而不是静默省略。
- 标签一类（`tag`）是唯一**没有输入文档**的记录：`packaging.tags` 是一组从
  "解释器 + ABI 表 + 平台表"到有序标签表的纯函数，因此语料是一列参数元组，
  两侧回答同一个问题（见 6.12）。62 个用例 + 6 条声明分歧。
- M8 加 `pylock`（PEP 751 锁文件）与 `meta_values`（核心元数据的逐值比对）：
  锁文件语料是 27 条手工接受 + 51 条手工拒绝 + 35 条单字符变异 + 1 条声明分歧，
  外加 **95 份从上面那 97 份真实索引响应派生的锁文件**（文件名、URL、sha256、
  大小、上传时间都是响应自己的，每份响应最多取 3 个版本、6 个文件），以及
  **6 份真实 `uv` 写出的锁文件**（`pylock_cases/uv/`，见 6.9、6.10）；
  `meta_values` 是把已有的 285 份元数据文档再按值过一遍，逐值一条记录。

## 2. 与目标 oracle（packaging 26.3）的一致性

```
oracle: packaging 26.3 (python 3.10.12), library targets packaging 26.3
toml reference reader: tomli
records: 122589 (61863 with a prerelease mode)
mismatches per source, kind and mode:
  none
OK: 122589 records agree with packaging 26.3
```

退出码 0。**0 不一致**。

## 3. 四后端一致性

```
reference: wasm
target      records      bytes  seconds  digest
wasm         122590   12425279     5.21  df7cd80290cfd38d
wasm-gc      122590   12425279     3.84  df7cd80290cfd38d identical
js           122590   12425279     4.03  df7cd80290cfd38d identical
native       122590   12425279     4.69  df7cd80290cfd38d identical
```

语料生成器在四个后端输出逐字节相同（sha256 前 16 位一致）。重复运行的
js 输出与捕获文件 md5 一致（`b9d0df199cfe94cdd42fcb64b5787b8a`），即生成
过程可重复。

## 4. 多 oracle 漂移矩阵

同一份语料在不同 `packaging` 版本下回放（`tools/oracle_matrix.py`）：

| packaging | records | differences | fatal | causes |
| --- | ---: | ---: | ---: | --- |
| 24.2 | 122589 | 4492 | 0 | auto-prerelease-admission x1749, compatible-release-range x3, exclusive-ordered-comparison x209, filename-grammar x142, index-scan x1, license-expression x153, marker-evaluation x1998, marker-grammar x184, metadata-rules x1, oracle-crash x28, tag-generation x24 |
| 25.0 | 122589 | 2754 | 0 | auto-prerelease-admission x1749, compatible-release-range x3, exclusive-ordered-comparison x209, filename-grammar x142, index-scan x1, license-expression x153, marker-evaluation x357, marker-grammar x87, metadata-rules x1, oracle-crash x28, tag-generation x24 |
| 26.0 | 122589 | 844 | 0 | compatible-release-range x3, exclusive-ordered-comparison x209, filename-grammar x142, index-scan x1, license-expression x66, marker-evaluation x285, marker-grammar x87, oracle-crash x27, tag-generation x24 |
| **26.3（目标版本）** | 122589 | **0** | **0** | — |

四个 oracle 都能回放全部 122 589 条记录，fatal 都是 0（旧版本按 `--tolerate-drift`
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

M8 收尾时把核心元数据语料逐条回放，又查出**三处**库与 `packaging` 26.3 不一致的
行为。三处都先在 `packaging` 上复现、确认是库错，再改，然后各配一条语料样例与
一处变异探针：

| 缺陷 | 现象 | 原因 |
| --- | --- | --- |
| `Name` 可以下划线结尾 | 库接受 `Name: demo_`，`packaging` 报 `InvalidMetadata(field "name")` | 名称文法的收尾判断写成了 `is_ascii_alphanumeric(c) \|\| c == '_'`；`_` 只在名称**中间**合法（`demo_1` 两侧都接受） |
| `Provides-Extra` 同上 | 库接受 `Provides-Extra: demo_` | 同一个判断函数 |
| `Keywords` 分段未按 Python 去空白 | `Keywords: a,\u{0b}b` 在库里得到 `["a", "\u{0b}b"]`，`packaging` 得到 `["a", "b"]` | 分段用 RFC 5322 的 WSP（空格与制表符）去空白，而 `packaging` 用 `str.strip()`，后者还包含垂直制表符、换页符、C0 信息分隔符与各类 Unicode 空格 |

三处都补了语料（`metadata_cases/43…46`）并把原先记录旧行为的断言**反转**而不是
删掉，因此修复本身也被断言。第二处与第三处是同一个判断函数和同一个去空白函数，
反转后"`_` 只在中间合法"与"哪些字符算空白"都被逐值钉住。

写标签语料时又查出**一处**同类缺陷，而且它的成因是语料本身：

| 缺陷 | 现象 | 原因 |
| --- | --- | --- |
| wheel 标签大小写未归一 | 库把 `Zope.Interface-5.4.0-CP311-CP311-Linux_x86_64.whl` 的标签读成大写，`packaging` 的 `Tag` 在构造时把三段全部小写 | `parse_tag_set` 直接拼接原文。语料里**每一个**文件名（手工的与真实的）都写小写，因此这条差异此前一次都没被触发 |

补了 5 个大小写混写的文件名（其中两个连项目名也是大写），语料从 122 516 条涨到
122 521 条，并加了 `wheel-tag-case-not-normalized` 探针把它钉住：修复前那处注入
是**绿的**。这条缺陷值得单独记一笔，因为它说明"0 不一致"的作用域只有语料覆盖到
的地方——两侧对同一个拼写都不产生输入时，语料无法就那个拼写表态。

## 5.5 语料是否有牙：变异探针

0 不一致只有在"对照能失败"的前提下才有意义。`tools/mutation_probe.py` 向库
里注入 41 处**故意缺陷**（涵盖 M0–M12 的行为），重跑语料并断言 harness 报错。下表是当前语料下的实测检出条数（探针自己打印的那一列）：

| 注入的缺陷 | 检出条数 |
| --- | ---: |
| `canonicalize_name` 丢掉尾部/首部分隔符 | 111 |
| 标签排序退回默认 `String` 比较（按长度） | 231 |
| wheel 标签不转小写（PEP 425 的 `Tag` 构造时全小写） | 105 |
| 自由线程 ABI 识别失效（`abi3t` 退回 `abi3`） | 3 |
| 空平台表不再被拒绝（三条声明分歧失效） | 1 |
| 生成的标签不转小写 | 3 |
| `abi3` 的历史回溯段（到 `cp32`）不再生成 | 12 |
| 版本键形式保留尾部零 | 401 |
| wheel 项目名不做规范化 | 416 |
| sdist 从第一个连字符切分 | 23 |
| local 文本段按长度比较 | 1 |
| 标记环境里的 `extra` 不做规范化 | 6 |
| 标记环境里的集合成员不做规范化 | 6 |
| `in` 的左右操作数调换 | 87 |
| 标记词汇表漏掉 `extras` | 258 |
| 依赖行里的标记不做校验 | 906 |
| SPDX 标识符区分大小写 | 831 |
| 内联表允许换行（TOML 1.1 行为） | 1 |
| 多行字符串吞掉首字符 | 3 |
| TOML 整数退化为 32 位 | 1 |
| PEP 639 的 `License-Expression` 与 `License` 冲突被放行 | 1 |
| PEP 639 的 `License-Expression` 与 `License ::` 分类器冲突被放行 | 1 |
| `Metadata-Version` 门槛失效（未知字段与未知版本被放行） | 1 |
| `Requires-Dist` 的值不再解析 | 4 |
| 重复的 JSON 成员名被接受（真实分歧消失） | 1 |
| 目录扫描退回默认 `String` 顺序（按长度） | 1 |
| 项目名可以下划线结尾（`Name: demo_` 被放行） | 2 |
| `Keywords` 分段只按 WSP 去空白 | 2 |
| `created-by` 可以缺席 | 2 |
| 文件记录可以没有 `hashes` | 1 |
| `upload-time` 的偏移不做校验 | 2 |
| 源树旁允许出现 `version` | 1 |
| 文件列表条目必须给 `version` | 1 |
| `lock-version` 接受未实现的次版本 | 2 |
| 锁文件条目允许两个来源并存 | 4 |
| 锁文件记录顺序改成 wheels 在前 | 20 |
| 锁文件文件名不从 URL 推导 | 8 |
| 解析器忽略 PEP 425 标签 | 3 |
| 解析器忽略 `Requires-Python` | 10 |
| 解析器忽略预发布策略 | 12 |
| 预发布策略恒为允许 | 2038 |

41/41 全部检出。**检出条数低不等于覆盖弱，但也不等于覆盖强**：一条记录只验一次
的行为，检出数就是 1，而它同时也是"那条样例被改坏就再也验不出"的信号。因此这张表
里检出数是 1 的每一行，都应当读成"目前只有一处样例钉住它"，而不是"这处行为不重要"：

- 两个 TOML 探针各 1 条：它们的现象只在单个样例上出现（内联表换行、超 64 位整数）；
- 两条 `License-Expression` 冲突探针各 1 条：只有一个样例能同时带上冲突的两个字段；
- `local` 文本段按长度比较 1 条、重复 JSON 成员名 1 条、目录扫描顺序 1 条、
  `Metadata-Version` 门槛 1 条、空平台表 1 条、源树旁的 `version` 1 条、
  文件列表条目的 `version` 1 条、文件记录没有 `hashes` 1 条：同上。

这些行的共同风险是"样例被改坏后探针从检出变成漏检"，所以探针的判定不是"条数大于
某个阈值"，而是"必须大于 0"——掉到 0 就会失败并点名是哪一处注入。

新加的五条锁文件探针里有**一条**第一次跑就是 `NOT DETECTED`，而且它抓到的
是语料而不是库：钉住"来源互斥"的那份样例同时带了 `version`，于是把互斥检查
关掉之后文档仍然被版本规则拒掉——**一条样例只有在它除此之外完全合法时才钉得
住那条规则**。补了 4 条不带 `version` 的互斥样例（每对成员一条）之后，检出
条数从 1 变成 4。这是"0 不一致只有在对照能失败的前提下才有意义"的一个具体
例子：探针不只在核对库，也在核对语料是否真的钉住了它声称钉住的东西。

同类的漏洞在标签那一轮又出现了一次，这次方向相反：库错、语料漏。`packaging` 的
`Tag` 在构造时把三段全部小写，而库直接拼接原文，差分实验却一次都没报——因为语料里
每一个文件名（手工的与真实的）都写小写。补了 5 个大小写混写的文件名之后，
`wheel-tag-case-not-normalized` 才从"绿"变成"检出 105 条"。

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
| `moon check/build/test --deny-warn`（wasm / wasm-gc / js / native） | 全部通过，每个后端 **277 个测试块全部通过**（合计 1108） |
| `moon run examples/basic`（四后端） | 通过 |
| `moon run examples/diff`（四后端） | 122 517 行语料，四端字节一致 |
| `moon run examples/metadata-check`（四后端） | 四端字节一致（md5 `2cedc437f5b3`） |
| `moon run examples/resolve`（四后端） | 四端字节一致（md5 `e58c1ff44ab6`） |
| `moon run examples/audit`（四后端） | 四端字节一致（md5 `9d3cadf92d80`） |

## 6.5 各阶段新增能力的覆盖

每一阶段都不是"新写一套验证"，而是**只增加记录类型**，被测代码换、验证方法
不换。到 M12 为止的记录构成（全部对 `packaging` 26.3，**0 不一致**，合计 122 589，
下表逐类相加即得该数）：

| 记录类型 | 条数 | 对照的 packaging API | 来源 |
| --- | ---: | --- | --- |
| `contains` | 60 870 | `SpecifierSet.contains` | curated + generated + pypi（3 种预发布模式） |
| `cmp` | 13 427 | `Version` 比较 | curated + generated + pypi |
| `parse` | 10 132 | `Version` | curated + generated + mutated + pypi |
| `marker_eval` | 8520 | `Marker.evaluate(env)` | curated + mutated × 5 套环境 |
| `canon` | 6159 | `canonicalize_name` / `canonicalize_version` | curated + mutated |
| `file` | 4950 | `parse_wheel_filename` / `parse_sdist_filename` | curated + mutated + pypi |
| `req` | 4662 | `packaging.requirements.Requirement` | curated + mutated + pypi（600 条真实 `Requires-Dist`） |
| `marker` | 4575 | `packaging.markers.Marker` | curated + mutated + 471 条真实标记 |
| `license` | 4086 | `packaging.licenses.canonicalize_license_expression` | curated + mutated |
| `spec` | 2491 | `SpecifierSet` | curated + generated + mutated + pypi |
| `filter` | 993 | `SpecifierSet.filter` | curated + generated + pypi |
| `toml` | 83 | 参考实现 `tomli`（接受/拒绝 + 重序列化） | 83 个 TOML 文档 |
| `meta_values` | 915 | `Metadata.from_email` 的**逐值**结果 | 46 条手工规则样例 + 239 份真实 PyPI `METADATA` |
| `meta` | 285 | `Metadata.from_email(data, validate=True)` | 46 条手工规则样例 + 239 份真实 PyPI `METADATA` |
| `pylock` | 215 | PEP 751 的**第二份读法**（`tools/fetch_pylock_corpus.py` 里独立重算） | 27 条手工接受 + 51 条手工拒绝 + 35 条变异 + 1 条声明分歧 + 95 份由真实索引响应派生 + 6 份真实 `uv` 输出 |
| `tag` | 62 | `packaging.tags` 的六个函数（参数逐项注入，不探测宿主） | 62 组参数：`cpython` 18 / `mac` 15 / `generic` 9 / `pure` 7 / `compatible` 7 / `select` 6 |
| `tag_divergence` | 6 | —（声明分歧，非断言） | curated |
| `index` | 118 | 规范本身（写成一处投影，Python 侧独立重算） | 21 条手工文档 + 97 份真实 PEP 691 响应 |
| `index_dir` | 5 | 规范本身（`parse_wheel_filename` / `parse_sdist_filename` + 排序规则） | 5 个目录清单 |
| `resolve` | 18 | 用 `packaging` 重写的候选选择与排序 | 18 组（需求 × 标签 × 解释器 × 预发布策略） |
| `order` | 3 | `Version` 全序 | curated + generated + pypi |
| `marker_env` | 5 | —（环境定义，非断言） | 5 套完整环境 |
| `meta_divergence` | 7 | —（声明分歧，非断言） | curated |
| `index_divergence` | 1 | —（声明分歧，非断言） | curated |
| `pylock_divergence` | 1 | —（声明分歧，非断言） | curated |

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

`meta` 记录问的是**裁决**与**往返**：两边接受与否是否一致，以及库自己重排出来的
文本在参考实现眼里是不是同一份元数据。这问不出**值**对不对——参考实现在读入时
就会去空白、规范化名称，一个库写错的拼写恰好被"用来检查它的那一步"抹平。M8 的
`Keywords` 去空白缺陷正是这个形状：`meta` 记录看不出任何异常，真值只有把文档交给
**库自己的解析器**再逐值比对才看得见。因此另有一类 `meta_values` 记录（915 条），
对一个文档逐值发一条：

| 字段 | 库侧的值 | 参考侧的值 |
| --- | --- | --- |
| `name` | `canonicalize_name(Metadata::name)` | `canonicalize_name(parsed.name)` |
| `version` | `Version::to_string` | `str(parsed.version)` |
| `keywords` | 规范化前的分段原文，逐条 + 一条条数记录 | `parsed.keywords` 逐条 |
| `provides-extra` | `Metadata::extras()`（PEP 685 比较形式） | `parsed.provides_extra` |
| `requires-python` | 解析后的 `SpecifierSet::to_string` | `str(parsed.requires_python)` |
| `requires-dist` | 条数 | `len(parsed.requires_dist)` |
| `summary` | 有无（`0`/`1`） | `parsed.summary is not None` |

两个细节是刻意的：列表字段额外发一条下标为 `-` 的**条数**记录，否则"少了一条"
会表现为"记录不存在"而不是差异；`requires-python` 比的是**解析后的集合**而不是
原文，因为真实元数据写的是 `>=2.6, !=3.0.*`（带空格），参考实现重排成
`!=3.0.*,>=2.6`，比原文只会报出没有规则约束的空格与顺序。参考实现拒了而库接受
的文档，`meta_values` 不报：那个差异已经由旁边的 `meta` 记录报过一次，逐值重复
会把真正的不一致埋掉。

另外两条已知差异不计入上面这张表，因为它们不影响裁决：`Author-email` /
`Maintainer-email` 在库里会被解析成 `(name, address)` 列表（参考实现原样存放），
解析失败只进 `diagnostics` 而不让文档失败。这条放宽是**实测驱动**的：239 份真实
文档里有 5 份（`kubernetes-10.0.0/10.0.1/10.1.0` 的 `Author-email: ` 与
`torch-1.0.0` 的 `Author-email: UNKNOWN`）会被更严的版本拒掉，而它们正是场景 1
要读的那种文档。

## 6.7 场景 1 的端到端输出

`examples/metadata-check` 把上面这些能力串成一个可运行产物：读真实 `METADATA`
（取自语料）和一份 `pylock.toml`（由库自己的 `Pylock::parse` 解析，M8），
对锁定版本与固定环境逐条判定，输出 `ok` / `OUT OF RANGE` / `not applicable` /
`not locked` / `UNPARSABLE` 与汇总。四份真实文档各自的用法：

```
lock file: pylock.toml, lock-version 1.0, 10 entries, 9 for this target, 1 for another; target: linux, CPython 3.11.9
   lock targets: sys_platform == 'linux'; extras the lock covers: 1, dependency groups: 2

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
（四后端 md5 一致：`2cedc437f5b3`）。锁文件里 `colorama` 带
`marker = "sys_platform == 'win32'"`，因此它被算作"为另一个目标锁定"而不是
"缺失依赖"——这条区分由 PEP 751 的 `marker` 承担，也是锁文件解析必须进库的原因。

输入是编译进去的：库只依赖 `moonbitlang/core`，core 没有文件系统包，示例因此
不从磁盘读文件（把常量换成文件或网络响应即可）。这一点在示例的注释里写明，不
含糊。

## 6.8 场景 2 的端到端输出

`examples/resolve`（570 行）是场景 2 的可运行产物：一份 PEP 691 索引响应 + 一张
目标平台标签表 + 一个 wheelhouse 目录，输出 yank 策略、每个被拒文件的**首条**失败
规则、候选排序与最终选择。下面是压缩后的实际输出（只删掉了重复行）：

```
== an index response
   demo_light, api-version 1.1: 14 entries, 13 installable, 1 not a distribution file
   versions (PEP 700): 0.9.0 1.0.0 1.1.0 1.2.0rc1 1.2.0 1.2.1 1.3.0b1 1.4.0 2.0.0
   demo_light-0.8.0.tar.bz2: INDEX_UNKNOWN_DIST
target: CPython 3.10.12, x86_64 linux, 12 tags, most specific first
== requirement  demo-light>=1.0,!=1.1.0
   12 file(s) of demo-light, 1 of another project, 11 offered to the resolver
   yanked, dropped: demo_light-1.2.0rc1-py3-none-any.whl / demo_light-1.4.0-py3-none-any.whl
   rejected 6 of 11:
      name             1     e.g. other_thing-1.0.0-py3-none-any.whl
      version          2     e.g. demo_light-0.9.0-py3-none-any.whl
      prerelease       1     e.g. demo_light-1.3.0b1-py3-none-any.whl
      requires-python  1     e.g. demo_light-2.0.0-py3-none-any.whl
      tags             1     e.g. demo_light-2.0.0-cp311-cp311-manylinux_2_17_x86_64.whl
   candidates 5, best first: 1.2.1 wheel cp310 / 1.2.1 wheel py3 / 1.2.0 wheel /
                              1.2.0 sdist / 1.0.0 wheel
   -> selected  demo_light-1.2.1-cp310-cp310-manylinux_2_17_x86_64.whl
      with no yank policy it would be demo_light-1.4.0-py3-none-any.whl
== the same requirement in a wheelhouse (no index, no network)
   /srv/wheels: 7 entries, 5 distribution file(s), 2 ignored
   files_for("Demo.Light") -> 5 file(s) (PEP 503 normalization)
   -> selected  demo_light-1.4.0-py3-none-any.whl
   default lister: INDEX_NO_FS at 0
```

这份输出里的每一条都是可核对的：

- **五条拒绝规则各出现至少一次**（`name` / `version` / `prerelease` /
  `requires-python` / `tags`），所以报告不是只有成功路径；
- **yank 策略真的改变了答案**：带策略选 1.2.1，不带策略会选被 yank 的 1.4.0，
  函数在同一份输入上同时打印两种结果，读者不必相信注释；
- **`INDEX_UNKNOWN_DIST` 与 `INDEX_NO_FS` 都是真实触发的**：`.tar.bz2` 不是 PEP 625
  的 sdist，默认的列目录函数没被注入时会报错而不是假装目录是空的；
- **目录与索引给出不同答案，而且原因写明了**：目录里没有 PEP 592 状态可读，
  1.4.0 因此胜出。

与场景 1 一样，输入是编译进程序的（core 没有文件系统包与 HTTP 客户端），
四后端输出逐字节一致（md5 `e58c1ff44ab6`）。

## 6.9 PEP 751 锁文件的对照方式：这里**没有**外部 oracle

前面每一类记录都能指着一个已有的实现说"对照的是它"：版本、约束、文件名、依赖行、
标记、许可证与核心元数据对 `packaging`，TOML 对 `tomli`。PEP 751 不一样——**没有
任何现成的 `pylock.toml` 读取实现可对照**。这一点必须写清楚，否则 0 不一致会被
误读成和别处一样强的证据。

因此 `tools/fetch_pylock_corpus.py` 是按 PEP 751 正文另写的**第二份读法**：它给出
裁决（接受/拒绝），并给出一个**投影**——把每个顶层成员、每个 `[[packages]]` 条目、
它的依赖与每个文件记录摊平成一行字符串。库这一侧由 `examples/diff` 的 `pylock`
记录发出同一个投影，两侧逐字符比对。投影只在一处写下来（生成器里），harness 直接
import 它，因此"两侧对同一套规则的解释"不会各自漂移。

它**能**抓的是库与"规范的一种读法"不一致；它**不能**抓的是两份读法同时读错同一段
规范。所以锁文件语料的价值在于别的三点：

1. **规则逐条落地**：51 条拒绝样例每条只违反一条规则（`lock-version` 类型、
   `environments` 的元素类型、标记文法、`requires-python`、三个名称列表、
   条目名与版本、来源互斥、VCS 的 `type`/`url`/`path`/`commit-id`、
   `hashes` 非空、依赖表、`size` 非负、`upload-time` 类型、文档根本不是 TOML），
   每条都配一个库自己的稳定错误码做单元测试。
2. **真实数据进得来**：95 份锁文件派生自真实索引响应，因此 `name` 缺失时从 URL
   取文件名、`path` 形式的文件记录、非 ASCII 项目名、多算法哈希这些路径都在真实
   形状上跑过，而不是只在手写的三行 TOML 上跑过；另有 6 份**不由本仓库生成**的
   `uv` 锁文件，见 6.10。
3. **分歧被断言而不是被容忍**：库现在只在 1 处故意与规范不同（未实现次版本的
   `lock-version` 拒绝而非警告）。原先登记的 7 处里有 6 处是库**比规范松**，逐条
   对照规范正文的 `Required?` 行重读之后已全部收紧，从分歧表降到普通拒绝样例
   （见 6.10）。剩下的这一处是库比规范**严**：规范对"支持主版本但不支持次版本"
   只说 SHOULD warn，而本库没有警告通道。它登记在 `pylock_cases/divergences.txt`，
   方向两边都断言：库哪天变得和规范一样松或一样严，记录立刻变成普通不一致。

写这份语料的过程中，被 harness 抓出的**四个**问题全部在**生成器**这一侧（也就是
我自己按规范写的那份读法），而不是库里：

| 生成器原先的判断 | 规范原文 | 结论 |
| --- | --- | --- |
| 文件记录必须有 `url` 或 `path` | `packages.wheels.url` 与 `packages.wheels.path` 都是 `Required?: no`，只有 `name` 是"最后一个路径分量不同时才需要" | 生成器过严；`name` 单独存在是合法文档 |
| `[packages.vcs]` 的 `url` 与 `path` 只能给一个 | 两者都是"另一个没给时**才**需要"，同时给满足两者 | 生成器过严 |
| `extras` 等名称必须先规范化 | PEP 685 规范化是写入方的义务；比较用 `canonicalize_name` | 生成器过严；未规范化拼写两侧都接受 |
| `packages.version` 在文件列表条目上可有可无 | `Required?: no`，只有 `SHOULD`／源树情形下 `MUST NOT` | 生成器过松；库原先要求它，曾是**分歧 D7**，现已按规范收紧（见 6.10） |

前三条改的是生成器（并各补一条接受样例），第四条升格为登记在案的分歧。这四条
恰好说明这类"自己写一份读法"的对照有什么价值：它把规范里那些**容易被想当然**的
`Required?` 行逐条逼出来，也把"我们到底哪里和规范不同"从注释变成了可执行的断言。

## 6.10 六处分歧的收敛，与真实 `uv` 写出的锁文件

库最初对 PEP 751 有 7 处与规范不同。把规范正文逐条调出来看，其中 6 处是库**比
规范松**，因此是缺陷而不是设计选择，已全部收紧：

| 原先的放宽 | 规范原文 | 现在 |
| --- | --- | --- |
| `created-by` 可缺可空 | `Required? : yes` | 缺失与空值都是 `CREATED_BY_REQUIRED`；`Pylock::created_by` 从 `String?` 改成 `String` |
| 文件记录可无 `hashes` | `Required? : yes`，"The table MUST contain at least one entry" | `FILE_HASHES_REQUIRED`（空表另有错误码） |
| `upload-time` 不校验时区 | "The date and time MUST be recorded in UTC" | 本地时间与任何非零偏移都是 `FILE_UPLOAD_TIME_NOT_UTC`；拼写仍原样保留，不把 `Z` 改写 |
| 源树旁的冗余 `version` | "MUST NOT be included when it cannot be guaranteed to be consistent with the code used (i.e. when a source tree is used)" | `PACKAGE_VERSION_NOT_ALLOWED`；`vcs` / `directory` 才算源树，`archive` 与本地 `path` 是文件而不是树 |
| 文件列表条目必须给 `version` | `Required? : no`，且只在版本稳定时才是 `SHOULD` | 不再要求；`PACKAGE_VERSION_REQUIRED` 从库里删除 |
| 未实现次版本的 `lock-version` 直接拒绝 | 支持主版本而不支持次版本 SHOULD warn，不支持主版本 MUST raise | **保留**：库没有警告通道，因此按 MUST 那一侧处理 |

收紧之后每一条都有普通语料样例钉住，而不是只把声明从分歧表里删掉：新增 1 条
"文件列表条目不给版本"的接受样例、2 条 UTC 拼写（`+00:00` 与 `-00:00`）的接受
样例，以及 4 条来源互斥样例（每对成员一条）。这 4 条样例本身**不带** `version`，
否则它们会被版本规则先拒掉——这一点是被变异探针当场抓出来的（见 5.5）。

**真实第三方锁文件。** `pylock_cases/uv/` 里是 6 份由 `uv 0.11.32`
（`uv export --format pylock.toml`）为 flask、requests、numpy、django、httpx、
cattrs 写出的 `pylock.toml`：50 个包、真实索引 URL、真实 sha256 与大小，
`wheels = [...]` 内联数组最长 77 KB。这是整个 PEP 751 语料里**唯一不由本仓库
生成**的输入；`pylock_cases/uv/provenance.txt` 记录来源与命令，文件按输入提交、
不再重新生成（`regenerate.sh` 只用于记录当时怎么做的）。库接受全部 6 份——这一点
是在上述 6 条规则**收紧之后**验证的，因此它同时是"收紧没有牺牲真实兼容性"的证据。

必须说清楚它**不**等于多了一份 oracle：`uv` 只写不读，不会给出裁决，所以这 6 份
补的是输入的独立性（PEP 751 之外的软件写出来的文档），而不是第二份读法。它们的
裁决仍然只有本仓库这一份，见 6.9 的第一段。

## 6.11 跨制品审计（`examples/audit`）的端到端输出

前面两节各自把一条链路串到底（元数据、索引），`examples/audit` 把三条链**合并成一次
决策**：一个需求、一份真实 `METADATA`、一份 PEP 691 索引响应、一份 PEP 751 锁文件、
一个明确的目标环境，输出 `Ready` / `Blocked` / `NotRequired` 与稳定问题码。它的四份
输入都是可复现的：`METADATA` 取自真实 PyPI wheel 的 PEP 658 边上文件，索引与锁按验收
条件写成固定输入（见 `docs/audit-scenario.md`）。

```
project: flask
requirement: Flask==0.12.5
disposition: ready
metadata: Flask 0.12.5
index: Flask, files=2, ignored=0, yanked=1
candidates: 1
selected: Flask-0.12.5-py3-none-any.whl
lock-versions: 0.12.5
issues: none
```

输出里值得单独指出的两行：`yanked=1` 说明被 PEP 592 标为 yanked 的候选**被排除而不是
被采用**（真实 Flask 0.12.5 之外的候选正是这种情况）；`issues: none` 是在名称、目标
Python、环境、锁定版本、最佳候选版本与 sha256 声明六项全部一致时才出现的结论，任何一项
不一致都会换成对应的稳定问题码，因此这十行不是"没有报错"，而是六条判定都过了。四后端
输出逐字节一致（md5 `9d3cadf92d80`）。

## 6.12 PEP 425 标签生成：唯一不读文档的一类记录

前面每一类记录的形状都是"一份输入 + 两侧各自的裁决"。标签不是：`packaging.tags` 是
一组**纯函数**，从"解释器 + ABI 表 + 平台表"算出有序标签表。所以 `tag` 记录是一列
参数元组（`name` 说明用哪个函数，`payload` 编码参数），harness 在回放时用同一组参数
调用参考实现，两侧比较**有序标签表**本身。这也是整份语料里唯一一个可以指着参考实现
说"同一句话问了两遍"的记录类型。

六个模式，62 组参数：

| 模式 | 组数 | 对照的 `packaging.tags` 函数 | 覆盖的点 |
| --- | ---: | --- | --- |
| `cpython` | 18 | `cpython_tags` | 显式 ABI → `abi3` → `none` 的顺序；`abi3` 回溯到 `cp32`；自由线程 ABI（`cp313t`）换成 `abi3t`；3.1（无稳定 ABI）、3.2（回溯边界）、只有主版本；旧式 `cp27mu`；大小写 |
| `mac` | 15 | `mac_platforms` | 10.x 逐个小版本回溯；11+ 的 `macosx_<major>_0_*` 与 x86_64 专属的 10.x 重放；早于架构支持年份的空结果（10.3 + x86_64、10.6 + ppc64、10.7 + ppc） |
| `generic` | 9 | `generic_tags` | `none` 的三元判断（`["NONE"]` 会**多加一条**同名标签）；ABI 表为空；多平台；大小写 |
| `pure` | 7 | `pure_python_tags` | `py312 → py3 → py311 … → py30` 的降序；只有主版本 |
| `compatible` | 7 | `compatible_tags` | `py*` 与平台表交叉、`<interpreter>-none-any` 的位置、`None` 与空串等价、纯 Python 尾巴 |
| `select` | 6 | `create_compatible_tags_selector` | 一个文件被多条标签命中时取**最早**的那条；无交集的文件不被选中；重复标签；空支持表 |

`select` 不比对"库算出的名次"，而是比对**参考实现自己的选择器挑出哪些条目、按什么
顺序**（投影是条目下标）。库这一侧用 `tag_rank` 排序后给出同样的列表，而 `tag_rank`
正是 `index.mbt` 的候选排序所用的规则——也就是说这一类记录同时验证了解析器那条链路里
"标签优先级"的实现。

**六条声明分歧**都是同一件事：参考实现在这些输入上会去读**运行中的机器**，而本库
拒绝猜测。

| 输入 | 参考实现 | 库 | 为什么这样定 |
| --- | --- | --- | --- |
| `cpython_tags` 的版本为空 | 读 `sys.version_info` | `TAG_VERSION_REQUIRED` | 调用方必须说明它在描述哪个解释器 |
| `compatible_tags` 的版本为空 | 读 `sys.version_info` | `TAG_VERSION_REQUIRED` | 同上 |
| `generic_tags` 的解释器名为空 | 问运行中的解释器是谁 | `TAG_INTERPRETER_REQUIRED` | 同上 |
| 三者的**平台表为空** | `platforms or platform_tags()`：读宿主平台（Linux 上还要看运行中的 libc） | `TAG_PLATFORMS_REQUIRED` | 这一条最值得记：空列表看起来像"没有平台"，在参考实现里却是"问本机"。两边对同一个 `[]` 回答不同的问题，所以本库按字面读并拒绝 |

平台表为空的这三条是被差分实验**当场抓出来**的：我原先把它们当成普通用例（库返回空
表、参考实现返回本机平台表），于是三条记录的投影必然不同，而且 fixture 里会写进生成
机器的平台表——一份依赖机器的 fixture。改成声明分歧之后，方向在两个方向都被断言。

`manylinux` / `musllinux` / `linux` 的平台表**不由本库计算**：那需要检测运行中的 glibc，
是 `platform_tags()` 的职责，仍然由调用方注入（与 `docs/experiment.md` 的"局限"一节
一致）。因此 `tag` 记录覆盖的是"给定平台表之后的展开与排序"，不包括"平台表怎么来"。

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
- 不证明覆盖全部现实输入：122 589 条是一次抽样，PyPI 的真实版本远多于 3000 个；
  真实 `METADATA` 只覆盖 239 份（有 PEP 658 边上文件的那些），且丢弃了 12 000
  字符以上的文档。
- 不覆盖**宿主探测**：标签的计算（PEP 425）已实现并逐条对照 `packaging.tags`，
  但 `sys_tags()` 与 `platform_tags()` 要读 `sys.version_info`、`sysconfig`、
  `EXT_SUFFIX` 与运行中的 libc，这三类输入仍由调用方注入（三条空输入被登记为
  声明分歧，见 6.12）。依赖求解与冲突回溯不做。
- TOML、许可证表达式与核心元数据的对照各用了一个参考实现（`tomli` 2.4.1、
  `packaging.licenses`、`packaging.metadata`），PEP 691 与 PEP 751 的对照则是
  "把规范写成一处投影、在两份实现里各算一遍"，其中 PEP 751 **没有**任何现成的
  实现可对照（见 6.9），因此它抓不出"两份读法同时读错同一段规范"。五者都不是
  规范文本本身；TOML、元数据、索引与锁文件的差异分别在
  `toml_cases/leniencies.txt`、`metadata_cases/divergences.txt`、
  `index_cases/divergences.txt` 与 `pylock_cases/divergences.txt` 中逐条登记。
- 锁文件语料里那 95 份派生文档是**构造**的：文件记录来自真实索引响应，但文档
  本身由生成器拼出。另外 6 份是 `uv` 真正写出来的文件，但 `uv` 只写不读、不给
  裁决，所以这 6 份的裁决仍然只有本仓库这一份读法（见 6.9、6.10）。
- 标记求值只对照了 5 套环境；`packaging` 在缺键时会回落到**宿主进程**的真实
  环境值，本库拒绝这个回落（不读运行时环境），因此"缺键"这一类行为是
  设计上的差异而非等价性结论。
- 旧版 `packaging` 的差异被归类为上游行为变更，这依赖"库对齐 26.3"这一
  前提；换目标版本就需要重新评估，`tools/oracle_matrix.py` 就是为此准备的。
