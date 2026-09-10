# Moon PyVersion — 项目申报书

> 本文为 AI 辅助整理的底稿，申报人已确认在此底稿上修改后提交；最终提交版本以本人改写确认为准。

## 项目名称

Moon PyVersion（MoonBit 模块 `123123213weqw/moon_pyversion`，版本 0.1.0）

## GitHub 地址

https://github.com/123123213weqw/moon-pyversion

## 简介

纯 MoonBit 实现的 Python 包版本库：按 PEP 440 对版本号做解析、规范化与比较，并按 PEP 440 version specifier 对候选版本做约束筛选。零第三方依赖，只使用 `moonbitlang/core`。它不是 SemVer 实现，也不替代已有的 SemVer 库；目标是在 MoonBit 中可靠回答“这个 Python 包版本是否满足这条版本约束”。

## 方向与通用性

属于“语言与开发工具”方向的软件供应链基础库。它只处理版本与约束本身，不绑定包名、平台标签、索引协议或网络行为，因此可被依赖检查工具、离线索引工具、升级评估工具等不同上层程序复用。

## 预期使用场景

1. **依赖清单检查**：工具先从上层的项目元数据中提取版本约束字符串，再对锁定版本逐个调用 `SpecifierSet::contains`，输出越界项清单。约束非法时返回稳定的 `VersionError` 与 UTF-16 偏移，便于定位；本库只判断单个版本是否满足约束，不解析整条依赖表达式。
2. **离线包索引筛选**：上层把本地镜像索引中的候选版本数组交给 `SpecifierSet::filter`，按 `>=1.0, !=1.4.*, <2.0` 之类的约束筛出可用集合，默认优先正式版、在没有任何匹配正式版时才回退到预发布，也可用 `prereleases=Some(false)` 显式排除预发布，从而减少无谓的下载与构建尝试。
3. **升级候选评估**：解析当前版本与候选版本，用 `compare` 排序并筛出落在目标区间内的候选，生成待测试短名单。本库明确不保证 API 兼容性、安全性与依赖可解性——它给的是“满足版本约束”这一层结论，是否真的可以升级仍由人工与集成测试决定。

## 核心功能

`Version::parse` / `normalize` / `to_string` / `compare`；支持 epoch、任意段数的 release、pre/post/dev 版本、local version、`v` 前缀、隐式补零与隐式 post（如 `1.0-1`）；`Version` 实现 `Eq`、`Compare`、`Show` 并保留调用方原始字符串。`SpecifierSet::parse` / `contains` / `filter`；支持 `==`、`!=`、`<`、`<=`、`>`、`>=`、`~=`、`===` 以及 `==`/`!=` 的 `.*` 通配后缀；提供 `prereleases` 显式开关。错误为稳定的 `VersionError`，只含错误码与偏移，不回显环境数据。

## 技术路线

解析器是按 UTF-16 偏移移动的 ASCII 游标，不引入正则依赖；所有整数组件经 `BigInt` 解析，避免组件溢出。比较按键序进行：epoch → 补齐后的 release → pre 相位与序号 → post → dev → local 分段。规范化为公开形式（去前导零、统一 `a`/`b`/`rc`/`.post`/`.dev`、`-`/`_` 归一、local 小写），release 段数保留，因此 `1.0` 与 `1.0.0` 输出不同但比较相等。所有约束以 AND 组合；`~=` 取含下界、上界由倒数第二个 release 段加一构成。CI 在 wasm / wasm-gc / js / native 四后端执行格式化检查、构建、测试与示例，并在 js 作业中用 Python `packaging==26.3` 对 2050 项排序与约束结果做独立黑盒对照（仅作行为参照，不引入其运行时代码）。

## 预计交付成果

公开可复现的 MoonBit 源码与 Apache-2.0 许可证；中文 README 与英文 API 契约；`examples/basic` 可运行示例与 `examples/oracle` 对照示例；覆盖核心路径的测试（现有 29 个测试块，含 PEP 440 官方规范化样例、非法输入拒绝、比较边例、各操作符、预发布规则与固定版本集上的反自反/反对称/传递性属性测试）；`tools/check_packaging.py` 独立对照脚本；四后端 CI；MoonCakes 发布。

## 明确不做的范围

不做 pip；不联网、不下载、不安装；不做完整依赖求解、候选生成或冲突回溯；不解析包名、extras、环境标记与平台标签；不提供 SemVer 兼容层；不为任意 legacy 版本字符串提供候选接口；不评估升级的安全性或 API 兼容性。`SpecifierSet` 只做约束筛选，不排序也不生成候选集。

## 原创 / 参考来源与许可证

本项目为独立原创的 MoonBit 实现，许可证 Apache-2.0。规则依据 PyPA 的版本规范（https://packaging.python.org/en/latest/specifications/version-specifiers/ ）。行为参照 [pypa/packaging](https://github.com/pypa/packaging)，其许可证为 Apache-2.0 或 BSD-2-Clause 双许可（择一），本项目未引入其源码、未复制其实现，仅用固定版本做黑盒结果对照，并已注明预发布默认策略随 packaging 26 发生变化。生态中的相邻项目：MoonCakes 上的 `mizchi/semver` 面向 Semantic Versioning；`Seedking/SemVer`（https://github.com/Seedking/SemVer ，Apache-2.0）是 MoonBit 的 SemVer 实现；`python123-ops/moondepsolve`（https://github.com/python123-ops/moondepsolve ，Apache-2.0）是 MoonBit 的依赖求解器与 CLI。三者与本库目标不同（前两者是 SemVer，后者是求解器），属相邻而非替代。

## 真实需求

MoonBit 生态已有 SemVer 工具，但在处理 Python 包索引、锁文件与依赖元数据时，需要的是 PEP 440 语义而不是 SemVer：epoch、任意段数 release、`~=` 与 `===`、`.*` 通配、local version 参与排序、以及预发布的特殊规则，都与 SemVer 不兼容。缺少一个零依赖的纯 MoonBit 版本判断库，就只能在上层重复手写字符串比较，容易在 `1.0` 与 `1.0.0`、预发布与正式版等边界上出错。

## 生态差异

与 SemVer 类库的差异是规则层面的：SemVer 固定三段且 build metadata 不参与优先级；PEP 440 允许任意段数 release，并把 local version 纳入排序，还有 epoch、`~=`、`===` 与通配后缀。与 `moondepsolve` 这类求解器的差异是职责层面的：求解器要在版本集合上搜索可行解并输出锁与冲突报告，本库只回答“单个版本是否满足一条约束”，不做搜索、不做回溯，也不生成候选集。这种取舍让它可以被复用在不同的上层工具里。

## 本人对方案的理解

我理解这个项目的价值不在于“再写一个版本比较函数”，而在于把 PEP 440 里容易被忽略的语义显式实现并验证清楚：epoch 的优先级、release 补齐零、无 pre 高于有 pre、`<` 与 `>` 对预发布和后发布的排除规则、local 分段的数值与文本混合比较。我也理解“满足版本约束”只是一个必要条件，不等于可安全升级，因此我刻意不把它包装成求解器或安全评估工具。测试上用 packaging 做独立对照，是为了验证我的实现而不是让它替我做决定；对照版本固定，是因为预发布默认策略会随上游变化。

## 提交前核对

- 仓库公开、构建与测试可复现、CI 覆盖四后端
- 有效提交数与作者归属按 GitHub 实际状态核对，不虚报
- MoonCakes 发布状态单独确认（仅 GitHub 不满足验收）
- 本文件为 AI 辅助底稿，最终提交版本由本人改写确认
