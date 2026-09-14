# Moon PyVersion — 项目申报书

> 本文为项目申报书底稿，最终提交版本以本人改写确认为准。

## 项目名称

Moon PyVersion（MoonBit 模块 `123123213weqw/moon_pyversion`，版本 0.1.0）

## GitHub 地址

https://github.com/123123213weqw/moon-pyversion

## 简介

纯 MoonBit 实现的 Python 包版本库：按 PEP 440 对版本号做解析、规范化与比较，并按 PEP 440 version specifier 对候选版本做约束筛选。零第三方依赖，只使用 `moonbitlang/core`。它不是 SemVer 实现，也不替代已有的 SemVer 库；目标是在 MoonBit 中可靠回答“这个 Python 包版本是否满足这条版本约束”。

## 方向与通用性

属于“语言与开发工具”方向的软件供应链基础库。它处理版本与约束，以及在此基础上长出来的两类离线元数据（核心元数据与索引响应）。**一切 I/O 与宿主环境都由调用方注入**：不联网、不读文件系统、不读运行时解释器环境，连平台标签表也是调用方按 `packaging.tags.sys_tags()` 的顺序传进来的，因此同一份输入在任何机器上得到同样的结论，可被依赖检查工具、离线索引工具、升级评估工具等不同上层程序复用。

## 预期使用场景

> **进度说明**：场景 1 与场景 2 的库内环节已经完成并有实测证据，场景 3 一直可用。每个场景后面都注明了当前边界，**没做的部分不当作已交付能力陈述**。

1. **依赖清单检查** `[已完成]`：`Metadata::parse` 读一份 `METADATA` / `PKG-INFO`（RFC 822 表头 + 正文，按 PEP 566 及 621 / 639 / 643 / 685 / 753 校验），`Metadata::requirements` 把 `Requires-Dist` 逐条交给 `Requirement::parse`，环境标记由 `Marker::evaluate` 在**调用方传入的**环境表上求值（库不读运行时环境，因此同一份清单在任何机器上得到同样的结论），再对锁定版本逐个调用 `SpecifierSet::contains`，输出越界项与不适用项清单。约束非法时返回稳定的 `VersionError`（含字段与偏移），便于定位；`Metadata::diagnostics` 另外报告"可用但已被规范取代"的字段。`pyproject.toml` 里的约束可用内置的 TOML 1.0 读取器取出，`pylock.toml` 另有 `Pylock::parse`（PEP 751，M8）逐成员校验，PEP 639 的许可证表达式与许可证文件路径也一并能校验。这份能力对 **239 份真实 PyPI `METADATA`**（真实 wheel 的 PEP 658 边上文件）逐条对照过 `packaging.metadata`，0 不一致。这条链路已经包成可运行示例 `examples/metadata-check`：四份真实 `METADATA` +
一份 `pylock.toml`（由库自己的 `Pylock::parse` 解析）+ 目标环境，输出逐条判定与汇总（含"这份锁文件有几条是为另一个平台锁定的"），四后端输出一致，CI 每次运行。
2. **离线包索引筛选** `[已完成]`：库已能用 `parse_wheel_filename` / `parse_sdist_filename` 从分发文件名解析出名称与版本（含真实 PyPI 文件名，900 条对照通过），并可用 `canonicalize_name` / `canonicalize_version` 得到归组与查找用的键形式；随后把候选版本数组交给 `SpecifierSet::filter`，按 `>=1.0, !=1.4.*, <2.0` 之类的约束筛出可用集合，默认优先正式版、在没有任何匹配正式版时才回退到预发布，也可用 `prereleases=Some(false)` 显式排除预发布，从而减少无谓的下载与构建尝试。索引响应（PEP 691 的 JSON 形式）与本地目录扫描也已经实现：`SimpleIndex::parse`
读索引文档，`LocalIndex::scan` 扫一个目录（列目录的函数由调用方注入，因为
`moonbitlang/core` 没有文件系统包），`resolve_candidates` / `select_best` /
`explain_rejection` 按名称、约束、预发布策略、`Requires-Python` 与 PEP 425 标签
筛出可安装的文件并给出一条确定的排序，同时说清其余每个文件是被哪条规则排除的。
这条链路对 **97 份真实索引响应**与 18 组候选解析与 `packaging` 逐条比对过，
0 不一致。它同样已经包成可运行示例 `examples/resolve`：一份索引响应 + 目标平台
标签 + 一个 wheelhouse 目录，输出候选排序、每个被拒文件的首条失败规则与最终选择，
四后端输出一致，CI 每次运行。
3. **升级候选评估**：解析当前版本与候选版本，用 `compare` 排序并筛出落在目标区间内的候选，生成待测试短名单。本库明确不保证 API 兼容性、安全性与依赖可解性——它给的是“满足版本约束”这一层结论，是否真的可以升级仍由人工与集成测试决定。

## 核心功能

**版本与约束**：`Version::parse` / `normalize` / `to_string` / `compare`；支持 epoch、任意段数的 release、pre/post/dev 版本、local version、`v` 前缀、后缀标签两侧的 `[-_.]?` 分隔符、隐式补零与隐式 post（如 `1.0-1`）；`Version` 实现 `Eq`、`Compare`、`Show` 并保留调用方原始字符串。`SpecifierSet::parse` / `contains` / `filter`；支持 `==`、`!=`、`<`、`<=`、`>`、`>=`、`~=`、`===` 以及 `==`/`!=` 的 `.*` 通配后缀；提供 `prereleases` 显式开关。错误为稳定的 `VersionError`，只含错误码与偏移，不回显环境数据。

**规范化与文件名**：`canonicalize_name`（PEP 503）、`canonicalize_version`（PEP 625，索引键与显示两种形式）、`parse_wheel_filename`（PEP 427，含 build 段与压缩标签集展开）、`parse_sdist_filename`（PEP 625）。

**需求行与环境标记**：`Requirement::parse` / `to_string`（PEP 508）覆盖两种操作数形式（`name [extras] 约束` 与 `name @ URL`）、可选标记；名称与 extras 按规范保留原样、约束按规范排序输出。`Marker::parse` / `to_string` / `evaluate` / `clauses` / `variables` 覆盖 14 个环境键的封闭词汇表（含集合型键 `extras` / `dependency_groups` 与点号别名）、`in` / `not in` 与六个比较运算符、`and` / `or` / 括号、Python 字面量式的引号与转义；版本型键按 PEP 440 比较，其余按字符串语义；`extra` 与集合成员按 PEP 685 / PEP 735 规范化。

**配置文件读取**：内置 TOML 1.0 解析器与规范重序列化器（`Toml::parse` / `get_*` / `to_string`），覆盖四种字符串、四种整数进制、浮点与特殊值、五种日期时间形状、数组、内联表、表与表数组、点号键，并保留文档顺序。

**锁文件**：`Pylock::parse`（PEP 751）读取 `pylock.toml`——`lock-version`、`environments`、`requires-python`、`extras`、`dependency-groups`、`default-groups`、`created-by` 与 `[[packages]]` 的必填性、类型和取值逐项校验，每包的 `marker` / `requires-python` 由 `is_applicable` / `requires_python_set` 判定；`Pylock::packages_named` / `files_for` / `dependencies_of` / `applicable_packages` / `accepts_environment` 供上层做“这份锁文件在我的环境下装哪些包”的判断。错误同样返回稳定码与结构序号。库在 **7 处**与规范有意不同（`created-by` 可缺可空、源树旁的冗余 `version`、文件记录可无 `hashes`、`upload-time` 记录原样而不校验 UTC、未实现的次版本 `lock-version` 直接拒绝而非警告、文件列表条目要求 `version`），每一条都登记在 `pylock_cases/divergences.txt` 里并在**两个方向上被断言**：库哪天变得和规范一样松或一样严，差分实验立刻报错。

**索引与候选解析**：`parse_json`（严格 RFC 8259）、`SimpleIndex::parse` / `wheels` / `sdists`（PEP 691）、`LocalIndex::scan` / `packages` / `files_for`（离线目录扫描，列目录函数注入）、`resolve_candidates` / `select_best` / `explain_rejection`（按名称、约束、预发布策略、`Requires-Python`、PEP 425 标签筛选与确定排序）。

**核心元数据**：`Metadata::parse` / `to_string`（PEP 566）：表头折行展开、版本门槛、字段的引入版本与多值/单值规则、`Requires-Dist`、`Requires-Python`、`Provides-Extra` 规范化、`Project-URL` 标签、许可证表达式与许可证文件路径、邮件地址列表、1.x 的废弃字段；拒绝时给出稳定错误码与偏移。`Metadata::requirements` / `requires_python` / `extras` / `is_compatible` / `diagnostics` 提供上层需要的视图。

**许可证**：`canonicalize_license_expression` / `is_valid_license_expression` / `canonicalize_license_file`（PEP 639），含 699 个许可证标识符与 79 个例外的查表、ASCII 大小写折叠、`LicenseRef-` / `DocumentRef-` 形式与嵌套上限。

库源码合计 8644 行（不含测试），测试 6389 行（251 个测试块）。

## 技术路线

版本与约束解析器是按 UTF-16 偏移移动的 ASCII 游标，不引入正则依赖；所有整数组件经 `BigInt` 解析，避免组件溢出。TOML 整数是 `Int64`（TOML 语义就是 64 位有符号），因此 `0xDEADBEEF` 在 wasm32 后端也能通过。比较按键序进行：epoch → 补齐后的 release → pre 相位与序号 → post → dev → local 分段。规范化为公开形式（去前导零、统一 `a`/`b`/`rc`/`.post`/`.dev`、`-`/`_` 归一、local 小写），release 段数保留，因此 `1.0` 与 `1.0.0` 输出不同但比较相等。所有约束以 AND 组合；`~=` 取含下界、上界由倒数第二个 release 段加一构成。库不使用任何第三方依赖，只依赖 `moonbitlang/core`，也不读时钟、环境变量或网络，因此同一输入在四个后端得到逐字节相同的输出。

CI 在 wasm / wasm-gc / js / native 四后端执行格式化检查、构建、测试与示例；另一个作业生成 **122 507 条**确定性语料（手工边界、按文法生成、单字符变异、97 个真实 PyPI 包的元数据、239 份真实 `METADATA`、105 份锁文件）并逐条回放给 CPython `packaging==26.3` 做独立黑盒对照，同时用参考实现 `tomli` 对照 TOML 的接受/拒绝与往返一致性，并在多个 packaging 版本上输出差异分类矩阵（仅作行为参照，不引入其运行时代码）。固定 26.3 是实测选定的：24.2 / 25.0 / 26.0 上分别有数千条差异，全部对应上游已发布的行为变更。四后端各自的语料做 sha256 比对，两个场景示例的报告也要求后端之间逐字节一致；每个提交的 fixture 还要先过一遍“与生成器一致”的校验（把重新生成的结果原地格式化后再比对），避免 fixture 被手工改动、或来自旧版生成器，却仍然被当成对照的输入。

## 验证方法

验证分三层，**哪一层是外部对照、哪一层不是，逐层写明**：

1. **外部 oracle 对照**：122 507 条记录逐条回放给 CPython `packaging==26.3`（3 000 个真实版本、500 条真实约束、600 条真实 `Requires-Dist` 原文、239 份真实 `METADATA`、900 个真实文件名、97 份真实索引响应），**0 不一致**；TOML 的接受/拒绝与往返一致性另外对照参考实现 `tomli`。
2. **按规范另写第二份读法**：PEP 691 索引文档、离线目录扫描、候选选择与 PEP 751 锁文件**没有**现成的 Python 实现可对照，这几类记录对照的是本仓库按规范写成的第二份读法（`tools/fetch_index_corpus.py`、`tools/fetch_pylock_corpus.py`），投影只写一处、由 harness 直接引用，两侧不会各自漂移。**PEP 751 尤其是这样**：没有任何现成的 `pylock.toml` 实现，因此那一类记录抓不出“两份读法同时读错同一段规范”，这一点写在 `docs/experiment-results.md` 6.9 里，不当作与 `packaging` 同级的证据。
3. **对照本身能不能失败**：`tools/mutation_probe.py` 向库里注入 **31 处**故意缺陷（名称规范化、标签排序、版本键形式、wheel/sdist 名称切分、local 段比较、标记规范化与词汇表、依赖行标记校验、SPDX 大小写、TOML 内联表与多行字符串与整数宽度、预发布策略、元数据名称与 `Keywords` 去空白、锁文件版本与来源互斥），31/31 全部被语料检出。探针在开始前会拒绝在已经修改过的工作树上运行——被中断的运行会把注入的缺陷留在源码里，那比不跑更糟。此外，逐值对照（`meta_values`，915 条）专门比对“解析出来的值”而不只是“接受与否”：参考实现在读入时就去空白、规范化名称，只比对裁决的话，一个写错的拼写会被**用来检查它的那一步**抹平。

语料中的 4 个 TOML 样例是参考实现的放宽（TOML 1.1 的内联表换行与尾随逗号、`\xHH` 转义、任意精度整数），库按 TOML 1.0 拒绝，这处分歧在两个方向上都被断言。

## 预计交付成果

公开可复现的 MoonBit 源码与 Apache-2.0 许可证；中文 README 与英文 API 契约；`examples/basic`、`examples/diff`（确定性语料发射器，2550 行）、`examples/metadata-check`（依赖清单检查，场景 1 的端到端证据，372 行）、`examples/resolve`（索引到可安装文件，场景 2 的端到端证据，570 行）、`examples/bench`（吞吐）五个可运行示例；覆盖核心路径的 **6 389 行测试 / 251 个测试块**（含 PEP 440 官方规范化样例、非法输入拒绝、比较边例、各操作符、预发布规则、标记求值、需求行文法、TOML 一致性、许可证表达式，以及固定版本集上的反自反/反对称/传递性属性测试），四个后端各自全通过（251 × 4）；

`tools/` 下 **9 个**差分实验脚本（`diff_packaging.py`、`target_parity.py`、`oracle_matrix.py`、`fetch_pypi_corpus.py`、`fetch_toml_corpus.py`、`fetch_metadata_corpus.py`、`fetch_index_corpus.py`、`fetch_pylock_corpus.py`、`mutation_probe.py`，合计 5 577 行 Python）与 `fixtures/` 真实语料（97 个 PyPI 包、83 份 TOML 文档、285 份核心元数据、21 条手工索引文档 + 97 份真实索引响应、105 份锁文件）；四后端 CI（verify 矩阵 + 独立的 differential 作业）；MoonCakes 发布 `[待确认]`——见下节。

## 后续规划

### `[进行中]` 收尾与发布

- 确认 MoonCakes 上的包名与版本（`moon.mod` 现为 `123123213weqw/moon_pyversion` 0.1.0）并执行首次发布、打 tag。**GitHub 绿灯不等于已发布**，这一项必须单独确认，本仓库当前没有 tag、也没有发布记录。
- 本文件与 `docs/submission-checklist.md` 按仓库实际状态过最后一遍。

### `[下一步]` 四个具体技术目标

1. **平台兼容性标签的计算**。标签目前只做匹配与排序（表由调用方传入）。下一步补一个**可注入**的展开接口：CPython 的 ABI 标签、manylinux / musllinux 的 glibc 版本与架构、`any` 平台。宿主探测仍留在调用方，保持“库不读运行时环境”这条边界不变——这正是它能在四个后端给出逐字节相同结果的原因。
2. **给 PEP 751 找到真正的外部对照**。锁文件语料现在的对照物是本仓库按规范另写的读法，抓不出“两份读法同时读错同一段规范”。下一步用 `uv` / `pip` 这类第三方工具对真实项目生成 `pylock.toml`，把**不是本仓库写的**文档纳入语料，让锁文件那一类记录也有独立对照物。这是当前验证体系里最明确的一块短板。
3. **场景 3 的可运行示例** `examples/upgrade-check`：读当前版本与候选版本列表，输出落在目标区间内的待测试短名单，并把“满足版本约束 ≠ 可以安全升级”做成报告里的显式声明，而不是注释里的免责条款。
4. **把 7 条锁文件分歧逐条定论**。现在是“声明并在两个方向上断言”，下一步是“逐条决定”：哪些应当收敛到规范（例如 `created-by` 改为必填、`upload-time` 真正校验 UTC、`packages.version` 在文件列表条目上放宽），哪些应当保留（例如未实现的次版本 `lock-version` 拒绝而非警告，因为本库没有警告通道）。决定之后，分歧数量应当**只减不增**，每减一条都由语料记录那次变更。

### `[长期]` 目标与它目前的证据状态

成为 MoonBit 侧消费 Python 生态（离线镜像、锁文件、依赖元数据）时默认的打包元数据基础库：稳定发布、语义化版本，并被至少一个上层工具实际复用。

**这一条目前没有证据**：仓库里没有已知的下游使用者，“可被复用”是设计上的取舍（零依赖、I/O 全部注入、错误稳定），不是既成事实。它是要争取的目标，不写进已完成的能力里。

## 明确不做的范围

不做 pip；不联网、不下载、不安装；不做完整依赖求解、候选生成或冲突回溯；不做平台标签的**计算**：库不会去探测宿主的平台与 glibc，标签表由调用方给出，库用它对候选做匹配与排序（这一项从 M7 起已实现）；不提供 SemVer 兼容层；不为任意 legacy 版本字符串提供候选接口；不评估升级的安全性或 API 兼容性；不读运行时真实解释器环境（标记求值只接受调用方传入的环境表）。`SpecifierSet` 只做约束筛选，不生成候选集。不实现 PEP 751 的安装算法本身：不挑选文件、不落盘、不做“同一名称的多个条目按目标收敛到一条”的判定（只提供 `is_applicable` / `applicable_packages` 这类判断材料）。

## 原创 / 参考来源与许可证

本项目为独立原创的 MoonBit 实现，许可证 Apache-2.0。规则依据 PyPA 的版本规范（https://packaging.python.org/en/latest/specifications/version-specifiers/ ）。行为参照 [pypa/packaging](https://github.com/pypa/packaging)，其许可证为 Apache-2.0 或 BSD-2-Clause 双许可（择一），本项目未引入其源码、未复制其实现，仅用固定版本做黑盒结果对照，并已注明预发布默认策略随 packaging 26 发生变化。生态中的相邻项目：MoonCakes 上的 `mizchi/semver` 面向 Semantic Versioning；`Seedking/SemVer`（https://github.com/Seedking/SemVer ，Apache-2.0）是 MoonBit 的 SemVer 实现；`python123-ops/moondepsolve`（https://github.com/python123-ops/moondepsolve ，Apache-2.0）是 MoonBit 的依赖求解器与 CLI。三者与本库目标不同（前两者是 SemVer，后者是求解器），属相邻而非替代。

## 真实需求

MoonBit 生态已有 SemVer 工具，但在处理 Python 包索引、锁文件与依赖元数据时，需要的是 PEP 440 语义而不是 SemVer：epoch、任意段数 release、`~=` 与 `===`、`.*` 通配、local version 参与排序、以及预发布的特殊规则，都与 SemVer 不兼容。缺少一个零依赖的纯 MoonBit 版本判断库，就只能在上层重复手写字符串比较，容易在 `1.0` 与 `1.0.0`、预发布与正式版等边界上出错。

## 生态差异

与 SemVer 类库的差异是规则层面的：SemVer 固定三段且 build metadata 不参与优先级；PEP 440 允许任意段数 release，并把 local version 纳入排序，还有 epoch、`~=`、`===` 与通配后缀。与 `moondepsolve` 这类求解器的差异是职责层面的：求解器要在版本集合上搜索可行解并输出锁与冲突报告，本库只回答“单个版本是否满足一条约束”，不做搜索、不做回溯，也不生成候选集。这种取舍让它可以被复用在不同的上层工具里。

## 本人对方案的理解

我理解这个项目的价值不在于“再写一个版本比较函数”，而在于把 PEP 440 里容易被忽略的语义显式实现并验证清楚：epoch 的优先级、release 补齐零、无 pre 高于有 pre、`<` 与 `>` 对预发布和后发布的排除规则、local 分段的数值与文本混合比较。我也理解“满足版本约束”只是一个必要条件，不等于可安全升级，因此我刻意不把它包装成求解器或安全评估工具。测试上用 packaging 做独立对照，是为了验证我的实现而不是让它替我做决定；对照版本固定，是因为预发布默认策略会随上游变化。

这轮补锁文件语料时我对这一点有了更具体的理解：**对照的价值完全取决于它能不能失败，而最容易出问题的地方是对照物本身**。PEP 751 没有现成的 Python 实现可对照，于是那份读法只能由我自己按规范写；写的过程中差分实验报出的 4 个问题全部在**我这边的读法**上、不在库里（我原以为文件记录必须有 `url` 或 `path`、以为 `[packages.vcs]` 的 `url` 与 `path` 只能给一个、以为 PEP 685 规范化是读者的义务、又以为 `packages.version` 一律可选），而规范正文的 `Required?` 行逐条否掉了我这几个“想当然”。另一头，逐值对照又会反过来抓库：三处元数据缺陷（`Name` 与 `Provides-Extra` 可下划线结尾、`Keywords` 分段没按 Python 去空白）只在“把文档交给库自己的解析器逐值比对”时才看得见，只比对接受与否的旧记录一条都没报。所以我把“对照物是哪来的、它证明了什么、它证明不了什么”当成交付物的一部分写进文档，而不是当成实验的附属说明。

## 提交前核对

- 仓库公开、构建与测试可复现、CI 覆盖四后端（verify 矩阵 + differential 作业）
- 有效提交数与作者归属按 GitHub 实际状态核对，不虚报（当前 `main` 上 37 个提交，作者均为本人账号）
- MoonCakes 发布状态单独确认：**当前没有 tag、没有发布记录**，仅 GitHub 不满足验收
- 本文件为底稿，最终提交版本由本人改写确认
