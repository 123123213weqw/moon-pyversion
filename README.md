# Moon PyVersion
[![CI](https://github.com/123123213weqw/moon-pyversion/actions/workflows/ci.yml/badge.svg)](https://github.com/123123213weqw/moon-pyversion/actions/workflows/ci.yml)

纯 MoonBit 实现的 **Python 打包元数据工具库**：解析、规范化、比较 PEP 440
版本与约束，并在此之上覆盖 PEP 503 名称规范化、PEP 427/625 分发文件名、
PEP 508 依赖行与环境标记、PEP 639 许可证表达式、TOML 1.0 与 core metadata
头部。零第三方依赖，仅使用 `moonbitlang/core`。

它不是 SemVer 实现，也不替代 `mizchi/semver`；不联网、不下载、不安装，
不做依赖求解——只做"把 Python 生态的元数据读懂"这一段。

## 目标

为 MoonBit 生态提供可嵌入的 Python 版本判断能力，例如：

- 检查依赖清单中的 `Requires-Python` 或依赖版本约束；
- 对离线包索引做版本筛选；
- 评估候选升级版本是否落入目标区间。

## 安装

已发布到 MoonCakes：`123123213weqw/moon_pyversion` 0.1.0
（`https://mooncakes.io/api/v0/modules/123123213weqw/moon_pyversion` 返回
`"version":"0.1.0"`、`"yanked":false`）。消费项目可直接：

```sh
moon add 123123213weqw/moon_pyversion@0.1.0
```

从源码复现：

```sh
git clone https://github.com/123123213weqw/moon-pyversion.git
cd moon-pyversion
moon run examples/basic --target js
moon test --target js --deny-warn
```

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

PEP 508 依赖行与环境标记：

```moonbit
let req = try! @pyversion.Requirement::parse(
  "Requests[Security]>=2.0,<3.0; python_version >= \"3.8\"",
)
println(req.name)                 // Requests
println(req.specifier.to_string())// <3.0,>=2.0

// 标记求值只接受调用方传入的环境表，不读运行时环境
let env = @pyversion.MarkerEnvironment::new()
env.set("python_version", "3.11")
let marker = try! @pyversion.Marker::parse("python_version >= \"3.8\"")
println(try! marker.evaluate(env)) // true
```

TOML 1.0（`pyproject.toml` / `pylock.toml`）与 core metadata 头部：

```moonbit
let doc = try! @pyversion.Toml::parse("[project]\nname = \"demo\"\n")
println(doc.get_string("project.name")) // Some("demo")

let meta = try! @pyversion.Metadata::parse(
  "Metadata-Version: 2.4\nName: demo\nVersion: 1.0\n",
)
println(meta.name)                       // demo
```

可运行示例位于 `examples/basic`。

## 验证命令

```sh
moon fmt --check
for t in wasm wasm-gc js native; do
  moon check --target $t --deny-warn
  moon build --target $t --deny-warn
  moon test --target $t --deny-warn
  moon run examples/basic --target $t
done
```

### 差分实验（可复现，见 `docs/experiment.md`）

```sh
# 1. 四个后端必须产出逐字节相同的语料
python -B tools/target_parity.py

# 2. 语料逐条回放给 CPython packaging 26.3（独立 oracle）
python -m pip install packaging==26.3
python -B tools/diff_packaging.py --oracle-version 26.3

# 3. 同一份语料在多个 packaging 版本下的漂移矩阵
python -B tools/oracle_matrix.py --oracle python3

# 4. 语料是否有牙：注入故意缺陷，断言对照能报错
python -B tools/mutation_probe.py

# 5. 可选：重新抓取真实 PyPI 语料
python -B tools/fetch_pypi_corpus.py
```

`tools/diff_packaging.py` 失败时按语料来源、记录类型和预发布模式分组打印
不一致，最多各留 5 条样本，并用 `--json` 输出机器可读报告。

## 已实现

- PEP 508 需求行（`requirements.mbt`）：`name[extras] specifier ; marker` 与
  `name[extras] @ url ; marker` 两种形式、extras 排序去重、约束规范化、
  packaging 仍然接受的 `foo(>=1.0)` 遗留写法；
- PEP 508 环境标记（`markers.mbt`）：**封闭词表**（拼错的键是语法错误而不是
  未知变量）、`and`/`or` 优先级、`not in` 的空格规则、Python 字符串转义解码、
  PEP 685 extras 规范化、按调用方提供的环境表求值；
- PEP 639 许可证表达式（`licenses.mbt`）：699 个 SPDX 标识符 + 79 个例外、
  大小写折叠、`LicenseRef-`/`DocumentRef-`、200 层嵌套上限、许可证文件路径校验；
- TOML 1.0（`toml.mbt`）：四种字符串、四种整数进制、日期时间、数组、内联表、
  表与表数组、点号键、规范重序列化；
- 打包元数据辅助（`utils.mbt`，对齐 packaging 26.3）：
  `canonicalize_name`（PEP 503 名称规范化）、`canonicalize_version`
  （PEP 625 两种形式：索引键与显示形式）、`parse_wheel_filename`
  （PEP 427，含 build 段与压缩标签集展开）、`parse_sdist_filename`（PEP 625）；
- 版本解析：epoch、release segments、pre/post/dev、local version、
  implicit post/dev/pre number、后缀标签两侧的 `[-_.]?` 分隔符
  （`1.0post1`、`1.0-post1`、`1.0a1-5`、`1.0a1post2dev3`）、`v` 前缀和
  首尾 ASCII 空白；
- 规范化：前导零去除、pre/post/dev 别名规范化、`-`/`_` 规范形式、
  本地段小写与数字段前导零去除；
- 比较：epoch 优先、release 补齐零、dev/pre/post/local 的 PEP 440 顺序；
- specifier：`==`、`!=`、`<`、`<=`、`>`、`>=`、`~=`、`===`、通配后缀、
  预发布边界规则与 `filter`；
- 稳定错误类型 `VersionError` 及格式化诊断：每个变体带稳定错误码与位置。

## 与 packaging 的一致性

不是自我声明，而是实测的：`examples/diff` 生成 **120 951 条**确定性记录
（手工边界、按文法生成、单字符变异、97 个 PyPI 包的真实元数据：3000 个版本、
500 条约束、600 条需求行、471 条真实标记、900 个分发文件名），逐条回放给
CPython `packaging 26.3`，**0 不一致**。TOML 记录另外对照参考实现 `tomli`，
逐条比较"接受/拒绝"与"重序列化后重新解析的结果"。

同一份语料在 24.2 / 25.0 / 26.0 上分别有数千条差异，全部按原因分类为上游
行为变更（自动预发布准入、`<`/`>` 的区间实现、`~=` 上界、26.3 的文件名
验收与标记语法收紧），`tools/oracle_matrix.py` 输出这张矩阵。

另外 `tools/mutation_probe.py` 会向库里注入 16 处**故意缺陷**并断言对照能报错，
16/16 全部检出 —— 即"0 不一致"不是因为对照失效。

实验设计、数据和查出的真实缺陷见 [docs/experiment.md](docs/experiment.md) 与
[docs/experiment-results.md](docs/experiment-results.md)。

## 边界

预发布策略对齐 `packaging 26.3`：`contains` 只有一个候选，默认允许满足
边界的预发布版本；`filter` 有完整候选集，默认优先正式版，没有匹配正式版时
才回退预发布版。约束显式包含预发布边界时会允许预发布候选。二者均可传
`prereleases=Some(false)` 强制禁用，或 `Some(true)` 允许。该默认行为不同于
旧版 packaging，不能把“落入区间”当作安全升级保证。

`===` 对已解析 `Version` 的规范化字符串做不区分大小写的相等判断；
不支持不可解析的任意 legacy 字符串候选。排序时 local 参与比较，但有序约束
忽略候选 local；有序约束本身不接受 local 后缀。

明确不做：pip、联网下载安装、完整依赖求解、冲突回溯、平台兼容性标签的匹配
与排序、读运行时真实解释器环境（标记求值只接受调用方传入的环境表）、
SemVer 兼容层。`SpecifierSet` 只做约束筛选，不生成候选集。整数组件当前由
MoonBit `BigInt` 承接；非 ASCII 的本地版本段会被拒绝。

已知边界（写清楚，不假装没有）：名称规范化与 wheel 名称校验按 ASCII 实现，
而 packaging 在这两处用 Unicode 感知的正则；TOML 按 1.0 实现，参考实现
`tomli` 2.4.1 有 3 处 TOML 1.1 放宽（内联表换行、尾随逗号、`\xHH` 转义），
这三条在 `toml_cases/leniencies.txt` 里显式列出并断言为"双方各自的行为"，
而不是悄悄放过。

## 与 mizchi/semver 的差异

| 项目 | Moon PyVersion | mizchi/semver |
| --- | --- | --- |
| 规则 | PyPA/PEP 440 | Semantic Versioning |
| 版本形状 | 任意段 release + epoch + pre/post/dev/local | `MAJOR.MINOR.PATCH` + prerelease/build |
| 本地版本 | `+local` 参与 PEP 440 排序 | `+build` 不参与 SemVer 优先级 |
| 约束 | PEP 440 specifier，含 `~=`、`===`、`.*` | SemVer range |
| 关系 | 相邻功能，处理 Python 包版本；不是替代品 | 面向语义化版本 |

## 许可证

Apache-2.0，见 `LICENSE`。

## 工程与申报资料

- [设计与边界](docs/design.md)、[来源及许可证](docs/provenance.md)。
- [项目申报书底稿](docs/proposal.md)（提交前由本人改写确认）。
- [人工申报准备清单](docs/proposal-draft.md)、[事实核对表](docs/applicant-notes.md)。
- [差分实验设计](docs/experiment.md)、[实验结果](docs/experiment-results.md)。
- [大项目规划](docs/plan.md)：从"版本比较器"扩为"离线 Python 打包元数据工具库"
  的里程碑、依赖图与统一验收门禁。
- [扩展工作项](docs/roadmap.md)：各模块的公开 API、验收标准与进展；
  未实现部分标注为 `[计划]`（M1 `utils.mbt` 已完成）。
- 工具链：`tools/diff_packaging.py`（对照 oracle）、`tools/target_parity.py`
  （四后端语料一致性）、`tools/oracle_matrix.py`（多 oracle 漂移矩阵）、
  `tools/fetch_pypi_corpus.py`（抓取真实 PyPI 语料）。Python 只用于测试，
  不是 MoonBit 库的运行依赖；CI 的 JS 作业会执行前三者。

