# Moon PyVersion
[![CI](https://github.com/123123213weqw/moon-pyversion/actions/workflows/ci.yml/badge.svg)](https://github.com/123123213weqw/moon-pyversion/actions/workflows/ci.yml)

纯 MoonBit 实现的 Python 包版本库：按 PEP 440 解析、规范化、比较版本，
并按 PEP 440 version specifier 做筛选。零第三方依赖，仅使用
`moonbitlang/core`。它不是 SemVer 实现，也不替代 `mizchi/semver`。

## 目标

为 MoonBit 生态提供可嵌入的 Python 版本判断能力，例如：

- 检查依赖清单中的 `Requires-Python` 或依赖版本约束；
- 对离线包索引做版本筛选；
- 评估候选升级版本是否落入目标区间。

## 安装

尚未在本文中确认 MoonCakes 发布成功。可先从源码复现：

```sh
git clone https://github.com/123123213weqw/moon-pyversion.git
cd moon-pyversion
moon run examples/basic --target js
moon test --target js --deny-warn
```

发布成功后才可在消费项目运行 `moon add 123123213weqw/moon_pyversion@0.1.0`。

开发时在 `moon.pkg` 中引入：

```text
import {
  "123123213weqw/moon_pyversion" @pyversion,
}
```

```moonbit
fn main {
  let v = try! @pyversion.Version::parse("v01.002-rc3+ABC_007")
  println(@pyversion.Version::to_string(v))
}
```

## 使用

```moonbit
let a = try! @pyversion.Version::parse("1.0")
let b = try! @pyversion.Version::parse("1.0.0")
println(a == b)

let spec = try! @pyversion.SpecifierSet::parse(">=1.0, !=1.4.*, <2.0")
let candidates = [
  try! @pyversion.Version::parse("0.9"),
  try! @pyversion.Version::parse("1.0"),
  try! @pyversion.Version::parse("1.4.1"),
  try! @pyversion.Version::parse("1.5"),
  try! @pyversion.Version::parse("2.0"),
]
let accepted = @pyversion.SpecifierSet::filter(candidates, spec)
```

可运行示例位于 `examples/basic`。

## 验证命令

```sh
moon fmt --check
moon check --target wasm --deny-warn
moon check --target wasm-gc --deny-warn
moon check --target js --deny-warn
moon build --target wasm --deny-warn
moon build --target wasm-gc --deny-warn
moon build --target js --deny-warn
moon test --target wasm --deny-warn
moon test --target wasm-gc --deny-warn
moon test --target js --deny-warn
moon run examples/basic --target wasm
moon run examples/basic --target wasm-gc
moon run examples/basic --target js
```

## 已实现

- 版本解析：epoch、release segments、pre/post/dev、local version、
  implicit post/dev/pre number、`v` 前缀和首尾 ASCII 空白；
- 规范化：前导零去除、pre/post/dev 别名规范化、`-`/`_` 规范形式、
  本地段小写与数字段前导零去除；
- 比较：epoch 优先、release 补齐零、dev/pre/post/local 的 PEP 440 顺序；
- specifier：`==`、`!=`、`<`、`<=`、`>`、`>=`、`~=`、`===`、通配后缀、
  预发布边界规则与 `filter`；
- 稳定错误类型 `VersionError` 及格式化诊断。

## 边界

预发布策略对齐 `packaging 26.3`：`contains` 只有一个候选，默认允许满足
边界的预发布版本；`filter` 有完整候选集，默认优先正式版，没有匹配正式版时
才回退预发布版。约束显式包含预发布边界时会允许预发布候选。二者均可传
`prereleases=Some(false)` 强制禁用，或 `Some(true)` 允许。该默认行为不同于
旧版 packaging，不能把“落入区间”当作安全升级保证。

`===` 对已解析 `Version` 的规范化字符串做不区分大小写的相等判断；
不支持不可解析的任意 legacy 字符串候选。排序时 local 参与比较，但有序约束
忽略候选 local；有序约束本身不接受 local 后缀。

明确不做：pip、联网下载安装、完整依赖求解、平台兼容性标签、包名规范化。
`SpecifierSet` 只做约束筛选，不生成候选集、不做回溯或冲突诊断。
整数组件当前由 MoonBit `BigInt` 承接；非 ASCII 的本地版本段会被拒绝。
这是库，不包含命令行下载器。

## 与 mizchi/semver 的差异

| 项目 | Moon PyVersion | mizchi/semver |
| --- | --- | --- |
| 规则 | PyPA/PEP 440 | Semantic Versioning |
| 版本形状 | 任意段 release + epoch + pre/post/dev/local | `MAJOR.MINOR.PATCH` + prerelease/build |
| 本地版本 | `+local` 参与 PEP 440 排序 | `+build` 不参与 SemVer 优先级 |
| 约束 | PEP 440 specifier，含 `~=`、`===`、`.*` | SemVer range |
| 关系 | 相邻功能，处理 Python 包版本；不是替代品 | 面向语义化版本 |

## AI 辅助开发披露

本项目代码、文档、测试和示例由 AI 辅助生成；自动测试不替代参赛者本人审阅。
PEP 440 行为参考 PyPA 规范与 `packaging` 的公开行为。任何申报材料均须由
本人核实改写，不得将 AI 草稿冒充本人撰写。

## 许可证

Apache-2.0，见 `LICENSE`。

## 工程与申报资料

- [设计与边界](docs/design.md)、[来源及许可证](docs/provenance.md)。
- [项目申报书底稿](docs/proposal.md)（AI 辅助底稿，提交前由本人改写确认）。
- [人工申报准备清单](docs/proposal-draft.md)、[事实核对表](docs/applicant-notes.md)。
- `tools/check_packaging.py` 可选对照检查：需要 Python 和 `packaging==26.3`，
  运行 `python -B tools/check_packaging.py`，对比 2050 个版本排序/约束结果。
  Python 仅用于测试，不是 MoonBit 库的运行依赖；CI 的 JS 作业自动执行。

