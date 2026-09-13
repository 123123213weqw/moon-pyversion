# Moon PyVersion — 扩展工作项（按申报书格式）

> 本文件是**工作项清单**，沿用 [项目申报书](proposal.md) 的章节结构，说明"还要做什么、
> 做到什么算完成、怎么验收"。它不是申报书，也不直接提交。
>
> 现状与目标的区别在每节里显式标注：`[已有]` = 已实现并有验收证据，
> `[计划]` = 尚未实现。**在对应工作项落地之前，proposal.md 不得按本节的口径改写**，
> 否则又会变成"申报书承诺了库做不到的事"。

## 项目名称

`[已有]` Moon PyVersion（MoonBit 模块 `123123213weqw/moon_pyversion`，当前 0.1.0）

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

### `[计划]` 新增四个模块

| 模块 | 公开 API | 关掉哪个场景 | 估行数 |
| --- | --- | --- | ---: |
| `utils.mbt` `[已有]` | `canonicalize_name`、`canonicalize_version`、`parse_wheel_filename`、`parse_sdist_filename` | 场景 2 | 331 |
| `requirements.mbt` | `Requirement::parse`、`Requirement::to_string` | 场景 1 | ~260 |
| `markers.mbt` | `Marker::parse`、`Marker::evaluate`、`MarkerEnvironment` | 场景 1 | ~380 |
| `metadata.mbt` | `Metadata::parse`、`Metadata::requires_dist`、`Metadata::requires_python` | 场景 1（端到端） | ~200 |

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
- `tools/mutation_probe.py` 对 7 处故意注入的缺陷全部检出，证明语料对这部分
  行为有覆盖。

`utils_test.mbt` 在开发中抓到一处真实缺陷：标签排序用了 MoonBit 默认的
`String` 比较（先比长度），与 `packaging` 的 `sorted()`（按码点）不一致 ——
与之前 local 段比较是同一类问题。

## 技术路线

`[已有]` 版本解析用按 UTF-16 偏移移动的 ASCII 游标，不引入正则；整数组件经
`BigInt`；比较按键序。四后端 CI。87 916 条语料差分对照 `packaging 26.3`。

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

## 预计交付成果

`[已有]` 源码 876 行、测试 507 行（34 个测试块 × 四后端全通过）、
`examples/basic` `examples/diff` `examples/bench`、`tools/` 四个脚本、
`fixtures/` 真实语料、四后端 CI + 独立 differential 作业。

`[计划]` 新增：

- 源码约 **+1060 行**（四个模块），测试约 **+500 行**；
- 差分语料从 87 916 条扩到约 **12–13 万条**（新增四类记录 + 真实元数据）；
- `examples/` 新增一个"元数据检查"示例：读一份真实 `METADATA`，输出越界项与
  不适用项清单——即场景 1 的可运行证据；
- `fixtures/` 增加真实 `Requires-Dist` 与分发文件名两组数组；
- CI 的 differential 作业覆盖新记录类型。

## 明确不做的范围

`[已有，需要收缩]` 原口径列了"不解析包名、extras、环境标记与平台标签"，
扩展后**包名、extras、环境标记三项要做**，这段必须改写。

`[计划]` 收缩后的清单：

- 不做 pip；不联网、不下载、不安装；
- 不做完整依赖求解、候选生成或冲突回溯；
- 不做平台兼容性标签（wheel tag 的匹配与排序）——**仍不做**，
  `parse_wheel_filename` 只解析出 tag，不判断 tag 是否兼容当前平台；
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
- 为什么仍然不做平台标签与依赖求解（边界判断）；
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
