# Moon PyVersion — 扩展工作项（历史路线与当前状态）

> 2026-09-15 更新：M1–M11 已落地，当前模块版本 0.2.0。最新申报事实以
> `docs/proposal.md`、`README.md` 和 `tools/source_metrics.py` 为准；下文保留施工前的
> `[已有]` / `[计划]` 记录，用于说明范围如何扩展，不应再作为当前状态直接引用。

> 本文件是**工作项清单**，沿用 [项目申报书](proposal.md) 的章节结构，说明"还要做什么、
> 做到什么算完成、怎么验收"。它不是申报书，也不直接提交。
>
> 现状与目标的区别在每节里显式标注：`[已有]` = 已实现并有验收证据，
> `[计划]` = 尚未实现。**在对应工作项落地之前，proposal.md 不得按本节的口径改写**，
> 否则又会变成"申报书承诺了库做不到的事"。

## 项目名称

`[已有]` Moon PyVersion（MoonBit 模块 `123123213weqw/moon_pyversion`，当前 0.2.0）

`[计划]` 扩展后定位从"版本字符串比较器"改为 **Python 包元数据与版本工具库**。
包名与版本号是否一并升到 0.2.0，待扩展落地后再定。

## GitHub 地址

`[已有]` https://github.com/123123213weqw/moon-pyversion

## 简介

`[已有]` 纯 MoonBit 实现的 Python 包版本库：按 PEP 440 解析、规范化、比较版本，
并按 PEP 440 version specifier 做约束筛选，零第三方依赖。

`[计划]` 扩展为：纯 MoonBit 实现的 **Python 包元数据与版本工具库**，覆盖从
"一条依赖声明"到"一个版本是否满足约束"的完整链路：需求行解析（名称/extras/
约束/环境标记）、环境标记求值、包名规范化、版本键形式、分发文件名解析、
METADATA 头部解析。仍然零第三方依赖，仍然不做下载与求解。

## 方向与通用性

`[已有]` 属于"语言与开发工具"方向的软件供应链基础库，只处理版本与约束本身，
不绑定包名、平台标签、索引协议或网络行为。

`[计划]` 扩展后仍然保持"不绑定索引协议与网络行为"这条通用性，但**要开始绑定
包名与元数据的规范**（PEP 503 名称规范化、PEP 566 METADATA、PEP 427 wheel 文件名）。
理由是：真实工具使用这些能力时，包名规范化与版本判断是同一个调用链里的相邻步骤，
把它们留在库外，上层就得重写一遍，正是"实现太窄"的根因。

## 预期使用场景

三个场景都从"上层自己提取"改为**库内端到端可用**。当前实测状态用真实 PyPI
字符串验证过（见下方"验收证据"列）。

### 场景 1：依赖清单检查

`[现状：跑不通]` 申报书原口径是"上层先提取版本约束字符串"，因为库只认纯约束。
用真实 `Requires-Dist` 原文实测，全部被拒：

| 真实输入 | 当前结果 |
| --- | --- |
| `Werkzeug>=3.0.0` | REJECT(INVALID_OPERATOR) |
| `importlib-metadata>=3.6.0; python_version < "3.10"` | REJECT(INVALID_OPERATOR) |
| `requests[security,socks]>=2.0,<3.0` | REJECT(INVALID_OPERATOR) |
| `python-dotenv; extra == "dotenv"` | REJECT(INVALID_OPERATOR) |

`[计划]` 目标流程：读一个 `METADATA` / `PKG-INFO` → 逐条 `Requires-Dist` 解析为
`Requirement` → 用 `Marker::evaluate` 判断该依赖在此环境是否适用 → 用
`SpecifierSet::contains` 判断锁定版本是否越界 → 输出越界项与不适用项。

### 场景 2：离线包索引筛选

`[现状：跑不通]` 申报书原口径是"上层把候选版本数组交给 filter"，因为库不能从
分发文件名取版本。实测：

| 真实输入 | 当前结果 |
| --- | --- |
| `flask-3.0.3-py3-none-any.whl` | REJECT(EXPECTED_DIGITS) |
| `flask-3.0.3.tar.gz` | REJECT(EXPECTED_DIGITS) |
| `numpy-1.26.4-cp312-cp312-manylinux_2_17_x86_64.whl` | REJECT(EXPECTED_DIGITS) |

`[计划]` 目标流程：遍历本地索引目录 → 从文件名解析出 (name, version) →
按 `canonicalize_name` 归组 → 用 `filter` 按约束筛出可用集合。
版本键形式（`canonicalize_version` 的 key 形式）用于索引查找，当前完全缺失：
本库 `to_string("1.0.0")` 返回 `1.0.0`，而索引键是 `1`。

### 场景 3：升级候选评估

`[已有：可用]` 解析、排序、按区间筛选已经工作。扩展后多一项能力：
把"当前版本的 METADATA 里声明的依赖"和"候选版本的同类声明"对比，
找出**约束变严**的依赖，作为回归测试的重点。这一项依赖场景 1 的能力。

## 核心功能

### `[已有]` 版本与约束（876 行源码 / 8 个公开函数）

- `Version::parse` / `normalize` / `to_string` / `compare`；支持 epoch、任意段数
  release、pre/post/dev、local、`v` 前缀、后缀标签两侧的 `[-_.]?` 分隔符；
- `SpecifierSet::parse` / `contains` / `filter`；`==` `!=` `<` `<=` `>` `>=` `~=`
  `===` 与 `.*` 通配，可控预发布策略；
- `VersionError` 稳定错误码 + UTF-16 偏移。

### 各模块（M1–M8 均已落地）

| 模块 | 公开 API | 关掉哪个场景 | 实际行数 |
| --- | --- | --- | ---: |
| `version.mbt` `[已有]` | `Version::parse/normalize/to_string/compare`、`VersionError` | 场景 1、3 | 551 |
| `specifier.mbt` `[已有]` | `SpecifierSet::parse/contains/filter`、`Specifier` | 场景 1、3 | 394 |
| `utils.mbt` `[已有]` | `canonicalize_name`、`canonicalize_version`、`parse_wheel_filename`、`parse_sdist_filename` | 场景 2 | 368 |
| `requirements.mbt` `[已有]` | `Requirement::parse`、`Requirement::to_string` | 场景 1 | 411 |
| `markers.mbt` `[已有]` | `Marker::parse/to_string/evaluate/clauses/variables`、`MarkerEnvironment`、`validate_marker_text` | 场景 1、2 | 1032 |
| `toml.mbt` `[已有]` | `Toml::parse/get/…/to_string`（TOML 1.0） | 场景 1、2 | 1580 |
| `licenses.mbt` `[已有]` | `canonicalize_license_expression`、`is_valid_license_expression`、`canonicalize_license_file` | 场景 1 | 460 |
| `metadata.mbt` `[已有]` | `Metadata::parse/requirements/requires_python/extras/is_compatible/diagnostics/to_string` | 场景 1（端到端） | 1378 |
| `index.mbt` `[已有]` | `SimpleIndex::parse/versions/files/wheels/sdists`、`LocalIndex::scan/files_for`、`resolve_candidates` / `select_best` / `explain_rejection`、`parse_json` | 场景 2 | 1256 |
| `pylock.mbt` `[已有]` | `Pylock::parse/lock_version/created_by/packages_named/files_for/dependencies_of/is_applicable/applicable_packages/accepts_environment` | 场景 1、2 | 1280 |
| `audit.mbt` `[已有]` | `audit_package`、`PackageAudit::render`、稳定问题码 | 场景 1、2 端到端 | 332 |
| `tags.mbt` `[已有]` | `cpython_tags`、`generic_tags`、`pure_python_tags`、`compatible_tags`、`mac_platforms`、`tag_rank` | 场景 2 | 448 |

截至 M13，根目录生产 MoonBit 合计 **9778 行**（不含测试与示例，含 `audit.mbt` 332 行、
`tags.mbt` 448 行与 `upgrade.mbt` 284 行），测试 **7311 行**（`*_test.mbt`，293 个
测试块 × 四后端），示例 2862（`diff`）+ 372（`metadata-check`）+ 570（`resolve`）+
268（`upgrade-check`）+ 36（`audit`）+ 180（`basic`/`bench`）行，工具链 7103 行
Python（12 个脚本）。

**`utils.mbt` 设计要点** `[已完成，见下]`（已用 packaging 26.3 核实）：

- `canonicalize_name`：PEP 503，小写 + `-_.` 连续串归一为 `-`。
  已核实：`Flask→flask`、`importlib_metadata→importlib-metadata`、
  `zope.interface→zope-interface`、`Foo.Bar-Baz→foo-bar-baz`。
- `canonicalize_version`：**两种形式必须都提供**，已核实差异：

  | 输入 | key 形式（去尾零） | 显示形式（保留） |
  | --- | --- | --- |
  | `1.0.0` | `1` | `1.0.0` |
  | `1.0.0.post0` | `1.post0` | `1.0.0.post0` |
  | `1!2.0` | `1!2` | `1!2.0` |
  | `1.0+ABC` | `1+abc` | `1.0+abc` |

  注意与现有 `Version::to_string` 的关系：`to_string` 输出显示形式，key 形式是
  新能力，release 尾部零要额外去掉。
- `parse_wheel_filename`：`{name}-{version}(-{build})?-{python}-{abi}-{platform}.whl`。
  已核实的边界：`flask-3.0.3-1-py3-none-any.whl` 的 build 段是 `(1, '')`；
  `torch-2.4.0+cu121-cp311-cp311-linux_x86_64.whl` 带 local 段。
- `parse_sdist_filename`：`{name}-{version}.tar.gz` 或 `.zip`；
  `foo.tar.gz` 应被拒。

**`requirements.mbt` 设计要点**（已核实）：

- 语法：`name [extras] (约束 | URL) [; marker]`。
- **名称与 extras 保留原样，不做规范化**：`Requirement("Requests[Security]>=2")`
  的 `name` 是 `'Requests'`、extras 是 `{'Security'}`。只有在比较/查找时才用
  `canonicalize_name`。这一点必须照做，否则与 packaging 不一致。
- **约束部分要规范化排序**：`>=2.0,<3.0` 解析成 `<3.0,>=2.0`（已核实）。
  现有 `SpecifierSet` 保持输入顺序，需要为 `Requirement` 增加排序输出，
  或者直接复用 packaging 的排序规则——这是本模块唯一需要改动既有代码的地方。
- 有 URL 的形式（`name @ https://...`）要能解析并暴露 `url` 字段。

**`markers.mbt` 设计要点**（已核实，风险最高）：

- 环境变量共 11 个键：`implementation_name`、`implementation_version`、
  `os_name`、`platform_machine`、`platform_python_implementation`、
  `platform_release`、`platform_system`、`platform_version`、
  `python_full_version`、`python_version`、`sys_platform`。
- 操作符：`in`、`not in`、`<`、`<=`、`==`、`!=`、`>=`、`>`，加 `and` / `or` / 括号。
- **`<` / `>` / `<=` / `>=` 不是字符串比较**：对版本型变量要按版本序比较。
  实测 `Marker('python_version < "3.10"')` 在 3.10 上为 `False`，而字符串序
  `"3.10" < "3.9"` 为 `True` —— 用字符串比较会给出相反答案。packaging 的算子表里
  `<` 和 `>` 直接返回 `False`，真正的比较发生在一步预处理里（把两侧转成 `Version`）。
- `in` / `not in` 是子串判定：`python_version in "3.8 3.9 3.10"` 为 `True`。
- **求值必须由调用方传入环境**，库不读真实解释器环境（否则结果不可复现，
  也无法在四后端一致）。这一条是硬约束。

**`metadata.mbt` 设计要点**：

- 只解析 RFC 822 风格头部（`Key: value`，可续行），不解析正文。
- `Requires-Dist` 的值逐条交给 `Requirement::parse`（可能解析失败，要保留原始串
  与错误，不能整份文件失败）。
- `Requires-Python` 交给 `SpecifierSet::parse`。

### `[已完成]` M1 落地情况

`utils.mbt` 已实现并通过验收：

- 4 个公开函数 + `WheelFilename` / `SdistFilename` 两个结构体，331 行；
- 12 个测试块（`utils_test.mbt`，约 190 行）；
- 差分语料新增 `canon`（名称 / 版本键两种形式）与 `file`（wheel / sdist / 其他）
  两类记录，共 **11 104 条**，其中真实文件名的 `pypi/file` 记录 900 条；
- 对照 `packaging 26.3` **0 不一致**；
- `tools/mutation_probe.py` 对故意注入的缺陷全部检出（M1 阶段为 7 处，
  现为 43 处），证明语料对这部分行为有覆盖。

`utils_test.mbt` 在开发中抓到一处真实缺陷：标签排序用了 MoonBit 默认的
`String` 比较（先比长度），与 `packaging` 的 `sorted()`（按码点）不一致 ——
与之前 local 段比较是同一类问题。

### `[已完成]` M2 + M3 落地情况

`requirements.mbt`（411 行 / 12 个测试块）、`markers.mbt`（1032 行 / 20 个测试块）
已实现并通过验收：

- PEP 508 需求行：`name [extras] (约束 | URL) [; marker]` 两种操作数形式，
  名称与 extras **保留原样**、约束**规范化排序**、URL 可含 `;`、空约束（`name; marker`）
  可用；拒绝路径由 `mutated/req` 4000 条单字符变异覆盖。
- PEP 508 环境标记：14 个键的封闭词汇表（含 `extras` / `dependency_groups`
  两个集合型键与点号别名）、`in` / `not in` / 比较运算符、`and` / `or` / 括号、
  Python 字面量式的引号与转义解码；版本型键走 PEP 440 比较，其余走字符串语义。
- **求值必须由调用方传入环境**：`MarkerEnvironment::new()` 是空的，缺键报
  `UndefinedEnvironmentName`。`packaging` 会回落到宿主进程的真实环境，这一
  差异是设计上的，已在文档中写明。
- 差分语料新增 `req`（4662 条）、`marker`（4575 条）、`marker_eval`（8520 条，
  5 套固定环境 × 标记）三类记录，对照 `packaging 26.3` **0 不一致**。
- 开发中抓到的真实缺陷：`platform.machine` 漏在词汇表里；`lhs in rhs` 的
  包含方向写反；引号字符串的结束判定；标记环境里的 `extra` / 集合成员
  未按 PEP 685 / PEP 735 规范化（后者由 16 个变异探针中的两个守着）。

### `[已完成]` M4 落地情况

`toml.mbt`（1580 行 / 15 个测试块）是 TOML 1.0 的解析器与**规范重序列化器**：

- 有序表、四种字符串、四种整数进制、浮点与特殊值、五种日期时间形状、数组、
  内联表、`[table]`、`[[array of tables]]`、点号键，全部保留文档顺序；
- 整数是 `Int64`（TOML 语义），因此 `0xDEADBEEF` 在 wasm32 上也能通过；
- 83 个一致性样例，裁决来自参考实现 `tomli` 2.4.1（`tools/fetch_toml_corpus.py`
  从 `toml_cases/*.toml` 生成 `fixtures/toml_corpus.mbt`）；
- 记录格式比其他类型多一层：库给出自己的重序列化文本，harness 用参考实现
  **重新解析**并与原文解析结果逐值比较，一条记录同时验证文法、取值与往返一致性；
- 4 个样例是参考实现的放宽（TOML 1.1 的内联表换行与尾随逗号、`\xHH` 转义，
  以及任意精度整数），库按 TOML 1.0 拒绝，登记在 `toml_cases/leniencies.txt`，
  记录状态 `lenient`，**两个方向都被断言**；若库变得同样宽松，状态变成
  `lenient-drift`，harness 立即报错。
- 开发中抓到的真实缺陷：多行基本字符串吞掉首字符；数字解析失败后符号已被消费
  导致 `-inf` 报错位置不对；内联表换行与"未闭合"共用错误码；`to_string`
  多输出一个空行；整数曾用 32 位 `Int`。

### `[已完成]` M5 落地情况

`licenses.mbt`（460 行 / 13 个测试块）实现 PEP 639：

- SPDX 表达式规范化：699 个许可证标识符与 79 个例外的查表、ASCII 大小写折叠、
  运算符大小写、`+` 后缀、`LicenseRef-` / `DocumentRef-` 形式与其中的 PEP 685
  规范化、200 层嵌套上限；
- `canonicalize_license_file` 按 PEP 639 校验许可证文件路径（不规范化）；
- 差分语料新增 `license`（4086 条，含 4000 条变异表达式），对照
  `packaging.licenses` **0 不一致**。

### `[已完成]` M6 落地情况

`metadata.mbt`（1300 行）是 `METADATA` / `PKG-INFO` 的读取与校验实现
（PEP 566，含 621 / 639 / 643 / 685 / 753 的修订）：

- RFC 822 风格表头 + 空行 + 正文；折行按 2.2.3 展开；表头名大小写不敏感、
  输出规范化；多值与单值字段分别处理；
- 版本门槛（`Metadata-Version` 必需，字段按引入版本放行）、未知字段拒绝、
  重复单值字段拒绝；每个拒绝都是稳定的 `InvalidMetadata(code, offset)`；
- `Requires-Dist` 逐条交给 `Requirement::parse`（单条失败即文档失败，但要指明
  是哪条规则的哪个字段）；`Requires-Python` 交给 `SpecifierSet::parse`；
  `Provides-Extra` 用 `canonicalize_name` 规范化；PEP 639 的许可证表达式与
  许可证文件路径复用 `licenses.mbt`；
- `Metadata::to_string` 是规范重排，`to_string(parse(x))` 是不动点，因此可以用
  "重新解析后取值一致"来做对照；
- **验收证据是真实数据**：239 份真实 `METADATA`（真实 wheel 的 PEP 658
  `.metadata` 边上文件，`fixtures/metadata_cache/` 是原始缓存）+ 46 条手工规则
  样例，逐条对 `packaging.metadata.Metadata.from_email(validate=True)` 回放，
  **0 不一致**；另有 7 条声明分歧登记在 `metadata_cases/divergences.txt`，
  由 harness 双向断言。

设计上的一处**实测驱动的放宽**值得单独记：最初 `Author-email` /
`Maintainer-email` 解析失败会让整份文档失败，239 份真实文档里有 5 份因此被拒
（`kubernetes-10.0.0/10.0.1/10.1.0` 的 `Author-email: `、`torch-1.0.0` 的
`Author-email: UNKNOWN`），而参考实现根本不看这个字段。这不符合场景 1
（"读一份真实 METADATA"）的目标，因此改成：空值等价于缺席，解析失败只写进
`diagnostics`，文档照常可用。

### `[已完成]` M7 落地情况

`index.mbt`（1256 行）把场景 2 补完：

- `parse_json`：严格 RFC 8259 读取器，数字保留源文本（不经过浮点），嵌套有上限，
  **重复成员名报 `JSON_DUPLICATE_KEY`** —— RFC 8259 只说名字"应当"唯一，这里按
  "必须"处理，因为被遮蔽的 `url` 或 `hashes` 正是索引消费者最不能漏掉的东西；
- `SimpleIndex::parse` / `wheels` / `sdists`：PEP 691 映射；既不是 wheel 也不是
  sdist 的条目报 `INDEX_UNKNOWN_DIST`，而不是被静默丢掉；
- `LocalIndex::scan`：目录扫描，列目录的函数**由调用方注入**（core 没有文件系统
  包），非分发文件一律忽略——与索引那条规则故意相反；
- `resolve_candidates` / `select_best` / `explain_rejection`：名称、约束、一次性
  算完的预发布策略、`Requires-Python`、PEP 425 标签四项过滤，排序为版本降序 →
  wheel 先于 sdist → 标签优先级 → PEP 427 build 号 → 文件名；最后一步是**额外
  加的**，因为 pip 把并列交给服务端顺序，而写锁文件的解析器必须确定；
- 验收证据：**97 份真实 PEP 691 索引响应** + 21 条手工文档 + 5 个目录清单 +
  18 组候选解析，全部在 Python 侧用 `packaging` 独立重算后逐条比对，**0 不一致**；
  另有 1 条声明分歧（重复 JSON 成员名）双向断言。

### `[已完成]` 语料扩展与"有牙"验收

- 语料从 87 916 条扩到 **122 640 条 / 122 641 行**：来源分布 curated 19 567、
  curated_bad 98、generated 20 652、mutated 34 397、pypi 47 677、pypi_index 97、
  pypi_lock 95、uv_lock 6；四后端逐字节一致。
- `tools/mutation_probe.py` 从 7 处扩到 **43 处**故意缺陷（覆盖 M0–M13），
  43/43 全部被语料检出；探针失败即实验失败。
- M8 之后的收尾：PEP 751 的 **7 条声明分歧收敛到 1 条**（6 条是库比规范松，
  逐条对着规范正文的 `Required?` 行收紧，并各补一条"除此之外完全合法"的普通
  样例钉住；保留的 1 条是库有意比规范严），语料补入 **6 份 `uv` 写出的真实
  `pylock.toml`**（不由本仓库生成的输入），变异探针同步从 31 处扩到 36 处，
  每条收紧各配一处。
- M12：PEP 425 标签**计算**落地（`tags.mbt`，448 行）。`cpython_tags` /
  `generic_tags` / `pure_python_tags` / `compatible_tags` / `mac_platforms`
  与 `tag_rank`（选择器规则，`index.mbt` 的候选排序改用它）逐条对照
  `packaging.tags`：**62 组参数 + 6 条声明分歧**，宿主探测仍然不做。
  写这一类语料时又查出一处库缺陷（wheel 标签大小写未归一，见
  `docs/experiment-results.md` §5），并补了 4 处变异探针。
- 多 oracle 矩阵（24.2 / 25.0 / 26.0 / 26.3）按原因分类上游行为变更，
  固定版本 26.3 仍为 **0 差异**。
- M13：场景 3 的升级候选评估（`upgrade.mbt` 284 行 + `examples/upgrade-check`
  268 行）。`upgrade_shortlist` 按固定顺序判 `unparsable` / `same` / `downgrade` /
  `out-of-range` / `prerelease` / `requires-python`，输出升序短名单与每个被弃候选的
  原因；预发布策略**经由区间**起作用，没有区间时策略不起作用。51 条用例 + 3 条
  不可判定输入由 `tools/fetch_upgrade_corpus.py` 生成，两侧比短名单**和原因**；
  另加 2 处变异探针。语料随之到 **122 640 条 / 122 641 行**，变异探针到 **43 处**。

## 技术路线

`[已有]` 版本解析用按 UTF-16 偏移移动的 ASCII 游标，不引入正则；整数组件经
`BigInt`；比较按键序。四后端 CI。122 640 条语料差分对照 `packaging 26.3`，另有 43 处故意缺陷的变异探针证明对照有效。

`[计划]` 新增模块沿用同一套技术路线与**同一套验收方法**，不新造轮子：

1. `[已有基础设施]` 差分 harness 直接扩展，不重写。语料发射器 `examples/diff`
   增加四类记录：

   | 新记录 | 内容 | 对照的 packaging API |
   | --- | --- | --- |
   | `req` | 需求行原文 → (name, extras, 约束规范化串, marker 有无, url) | `Requirement` |
   | `marker` | 标记原文 + 环境表 → 布尔值 | `Marker.evaluate(env)` |
   | `canon` | 名称/版本串 → 规范化结果 | `canonicalize_name` / `canonicalize_version` |
   | `file` | 分发文件名 → (name, version, build, tag 数) | `parse_wheel_filename` / `parse_sdist_filename` |

2. `[已有基础设施]` 真实语料几乎免费可得：`tools/fetch_pypi_corpus.py` 已经在抓
   `Requires-Dist` 原文（本文件场景 1 的实测输入就来自它），PyPI JSON 的
   `urls[].filename` 直接给出真实分发文件名。只需在现有脚本里多写一个输出数组。

3. `[新工作]` 语料里的需求行有真实世界噪声（大小写、extras、marker 组合），
   `mutated` 一类继续用单字符变异覆盖拒绝路径。

4. `[新工作]` marker 求值需要固定的环境表。倾向固化一组环境（当前 CI 的
   Python 版本 + 少量假想环境），写进语料，保证四后端与跨时间可复现。

5. `[已有基础设施]` `target_parity.py` 与 `oracle_matrix.py` 不改即可覆盖新记录。

## 交付成果

`[已有]` 源码 **9778 行**（不含测试）、测试 **7311 行**（293 个测试块 × 四后端
全通过）、`examples/basic` `examples/diff`（2862 行确定性发射器）
`examples/bench`、`examples/metadata-check`、`examples/resolve`、
`examples/upgrade-check`（268 行，升级短名单）、`examples/audit`（36 行，跨制品审计）、
`tools/` 十二个脚本（7103 行 Python，含 `source_metrics.py`、`fetch_tag_corpus.py`
与 `fetch_upgrade_corpus.py`）、`fixtures/` 真实语料
（97 个 PyPI 包 + 83 个 TOML 文档 + 285 份核心元数据 + 114 份手工锁文件 + 6 份真实 `uv` 锁文件）、四后端
CI + 独立 differential 作业。

`[计划]` 还差：

- `[已完成]` `examples/metadata-check`：读真实 `METADATA` + 一份 `pylock.toml`
  （`Pylock::parse`）+ 目标环境，输出越界项、不适用项与无法解析项清单，并报告
  锁文件里有多少条是为另一个目标锁定的——场景 1 的可运行证据，四后端输出一致，
  CI 已纳入；
- `[已完成]` `examples/audit`（36 行）+ `audit.mbt`（332 行）：把需求、真实
  `METADATA`、索引响应、锁文件与目标环境合并为一次 `audit_package` 决策，输出
  `Ready` / `Blocked` / `NotRequired` 与稳定问题码；四后端输出逐字节一致
  （md5 `9d3cadf92d80`），CI 已纳入。验收输入与边界见 `docs/audit-scenario.md`；
- `[已完成]` `examples/resolve`（570 行）：一份 PEP 691 索引响应 + 目标标签表 +
  一个 wheelhouse 目录，输出 yank 策略、每个被拒文件的首条失败规则、候选排序与
  最终选择——场景 2 的可运行证据，四后端输出一致，CI 已纳入（含逐后端比对）；
- `[已完成]` `pylock.mbt`（1280 行 / 32 个测试块，`docs/plan.md` 的 M8）：
  `pylock.toml`（PEP 751）的读取与校验——`lock-version` / `environments` /
  `requires-python` / `extras` / `dependency-groups` / `default-groups` /
  `created-by` / `[[packages]]` 全部成员的必填性、类型与取值校验，每包
  `marker` 与 `requires-python` 的应用判断，以及 20 余条稳定的
  `InvalidPylock(code, ordinal)` 错误码。PEP 751 自己打印的示例文档逐字节可读。
  差分语料同一轮补齐：**215 条 `pylock` 记录**（27 条手工接受 + 51 条手工拒绝 +
  35 条单字符变异 + 1 条声明分歧 + 95 份由真实索引响应派生的锁文件 + 6 份 `uv`
  写出的真实锁文件），由 `tools/fetch_pylock_corpus.py` 里按规范另写的第二份读法
  给出裁决与投影；分歧的收敛过程与那 6 份第三方文档写在
  `docs/experiment-results.md` 6.10 里。
  PEP 751 **没有**现成的 Python 实现可对照，这一点写在
  `docs/experiment-results.md` 6.9 里，不当作与 `packaging` 同级的证据；
- `[已完成]` `meta_values` 记录（915 条）：核心元数据的**逐值**比对。原先的
  `meta` 记录只比对裁决与重排往返，问不出"值对不对"——参考实现读入时就去空白、
  规范化名称，库写错的拼写恰好被用来检查它的那一步抹平。M8 回放语料查出的三处
  元数据缺陷（`Name` 可下划线结尾、`Provides-Extra` 同上、`Keywords` 分段未按
  Python 去空白）就是这样一条 `meta` 记录都看不出，只能逐值比出来。

## 明确不做的范围

`[已改写两次]` 原口径列了"不解析包名、extras、环境标记与平台标签"；其中**包名、
extras、环境标记三项在 M2/M3 做完**，**平台标签的匹配与排序在 M7 做完**（M7 的
`resolve_candidates` 正是按标签过滤并排序的）。仍然不做的是标签的**计算**：库不
探测宿主的平台与 glibc，标签表由调用方按 `sys_tags()` 的顺序传入。当前清单：

- 不做 pip；不联网、不下载、不安装；
- 不做完整依赖求解或冲突回溯（单个约束下的候选排序已有，跨包求解没有）；
- 不计算平台兼容性标签：`parse_wheel_filename` 解析出 tag，
  `resolve_candidates` 用调用方给的标签表匹配与排序，库自己不去问宿主是什么平台；
  M12 补上的是**展开**（`tags.mbt`：给定解释器、ABI 与平台表后生成有序标签表），
  `sys.version_info` / `sysconfig` / `EXT_SUFFIX` / 运行中 libc 这四类输入仍由
  调用方注入，三条"参考实现会去读宿主"的输入被登记为声明分歧；
- 不提供 SemVer 兼容层；不为任意 legacy 版本字符串提供候选接口；
- 不评估升级的安全性或 API 兼容性；
- 不读运行时真实解释器环境：marker 求值只接受调用方传入的环境表。

## 原创 / 参考来源与许可证

`[已有]` 独立原创 MoonBit 实现，Apache-2.0；规则依据 PyPA 规范，行为参照
`pypa/packaging`（Apache-2.0 / BSD-2-Clause），未引入其源码。

`[计划]` 需补充的规范引用：PEP 503（名称规范化）、PEP 566 / 核心元数据规范
（METADATA）、PEP 427（wheel 文件名）、PEP 508（需求行与标记）。
许可证结论不变，但 `docs/provenance.md` 要补这些来源。

## 真实需求

`[已有]` MoonBit 生态缺少 PEP 440 语义的版本判断能力。

`[计划]` 补强论据：缺的不只是"版本比较"，而是**整条链路的断点**。
MoonBit 若要消费 Python 生态（离线镜像、锁定文件、镜像元数据），
现有情况是从 `Requires-Dist` 原文到"这条依赖是否越界"之间每一环都得手写：
拆需求行、规范化包名、求值环境标记、从文件名取版本。本库把这一整段补齐。

## 生态差异

`[已有]` 与 `mizchi/semver`、`Seedking/SemVer` 是规则差异（SemVer vs PEP 440）；
与 `python123-ops/moondepsolve` 是职责差异（求解器 vs 单点判断）。

`[计划]` 不变。扩展后与 `moondepsolve` 的边界反而更清晰：求解器做搜索与回溯，
本库给它提供可信的输入层（规范化的需求与标记判定），二者可组合而非竞争。

## 本人对方案的理解

`[必须由本人撰写]` 本节不能由他人代写。扩展后需要本人补的新内容：

- 为什么把包名规范化与标记求值放进库里、而不是留在上层；
- 为什么标记求值坚持"环境由调用方传入"，以及这与可复现性测试的关系；
- 为什么把平台标签表交给调用方而不是让库去探测宿主，以及为什么依赖求解仍然不做；
- 对"版本键形式"与"显示形式"两种规范化为什么必须并存的理解。

## 分阶段实施与验收标准

每一阶段都必须保持现有验收标准不退化：四后端 `check/build/test/run` 全通过、
`tools/target_parity.py` 四端语料一致、`tools/diff_packaging.py` 对
`packaging 26.3` **0 不一致**。

### 阶段 1：`utils.mbt`（先行，无依赖）

- 产出：四个函数 + 测试 + `canon` / `file` 两类差分记录。
- 验收：真实分发文件名（含 `+local`、含 build 段）与 `canonicalize_*` 的
  输出逐条与 packaging 一致；`foo.tar.gz` 一类被正确拒绝。
- 完成后：场景 2 端到端可跑通。

### 阶段 2：`requirements.mbt`

- 产出：`Requirement` + 测试 + `req` 记录。
- 验收：真实 `Requires-Dist` 原文逐条解析一致（名称/extras **不**规范化、
  约束**要**规范化排序、URL 形式可用）。
- 完成后：场景 1 的解析环节可跑通。

### 阶段 3：`markers.mbt`

- 产出：`Marker` + `MarkerEnvironment` + 测试 + `marker` 记录。
- 验收：固定环境表下，版本型比较（`python_version < "3.10"` 类）、
  `in`/`not in`、`and`/`or`/括号 逐条与 packaging 一致。
- 风险最高，单独成阶段；若与 packaging 存在无法对齐的语义，如实记录为边界，
  不掩饰。
- 完成后：场景 1 完整可跑通。

### 阶段 4：`metadata.mbt` + 示例 + 文档

- 产出：`Metadata` + `examples/` 元数据检查示例 + proposal.md 按实际实现改写。
- 验收：对一份真实 `METADATA` 输出越界项与不适用项清单；示例在四后端可运行。
- 完成后：才能改写 proposal.md 的场景与"不做范围"两节。

## 风险

| 风险 | 说明 | 应对 |
| --- | --- | --- |
| marker 语义最复杂 | 版本型 vs 字符串型比较、`in` 的子串语义、`extra` 变量 | 单独阶段，差分语料优先覆盖 |
| `Requirement` 需要约束排序 | 现有 `SpecifierSet` 保持输入顺序 | 为规范化输出单独提供函数，不改变现有顺序语义 |
| 语料里 marker 需固定环境 | 否则不可复现 | 固化环境表写进语料 |
| 范围再次膨胀 | 依赖求解、平台标签容易被"顺手"加进来 | 严格按"明确不做"清单卡住 |
| 申报书与实现脱节 | 本轮已发生一次 | 只在阶段完成后改 proposal.md，并保留 `[已有]/[计划]` 标注直到全绿 |
