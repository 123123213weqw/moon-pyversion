# 申报前技术事实清单

> 这不是申报书，只记录提交前应逐项核实的事实。

## 项目事实

- 项目名：Moon PyVersion；
- 本地目录：`D:\Codex\moon-pyversion`；
- 仓库地址：`https://github.com/123123213weqw/moon-pyversion`；
- MoonCakes 包名：`123123213weqw/moon_pyversion`；
- 版本：`0.1.0`；
- 许可证：Apache-2.0；
- 依赖：仅 `moonbitlang/core`；
- 语言：MoonBit，源码扩展名 `.mbt`。

## 功能事实

- 已实现 PEP 440 版本解析、规范化、比较；
- 已实现 PEP 440 specifier 的解析、`contains`、`filter`；
- 支持 `==`、`!=`、`<`、`<=`、`>`、`>=`、`~=`、`===`；
- 支持 `==1.4.*`/`!=1.4.*` 通配后缀；
- 支持 epoch、pre/post/dev、local、implicit post、`v` 前缀；
- 错误类型为 `VersionError`，含稳定 code 与 UTF-16 偏移。

## 验证事实

- 已运行 `moon fmt --check`；
- 已运行 `moon check/build/test/run`（wasm、wasm-gc、js）；
- native 本地是否通过取决于本机 C 工具链；CI 仍覆盖 native；
- 测试块数量：219，四个后端全部通过（以实际运行结果为准）；
- 独立差分实验：122 516 条记录对照 CPython packaging 26.3，0 不一致；
  旧版本 oracle 的差异按原因分类记录，见 docs/experiment-results.md；
- Git 提交数量及归属须核对 GitHub main；不得把数量直接称为官方认可的有效提交。

## 范围事实

- 不做 pip、联网下载安装；
- 不做完整依赖求解器；
- 不做包名、extras、环境标记、平台标签；
- 不与 SemVer 互换，与 `mizchi/semver` 是相邻功能。

## 申报提醒

- 用本人语言改写申报书；
- 核实账号、提交数、测试数、CI 状态；
- 不要声称官方已认可或已发布；
- 搜索未命中不代表绝对无同类。
- 完整赛事与人工申报要求见 [提交核对表](submission-checklist.md)。
