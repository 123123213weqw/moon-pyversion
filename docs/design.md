# Moon PyVersion 技术设计与边界

## 目标

在纯 MoonBit 库中实现 Python 包版本判断的核心子集：

1. PEP 440 版本解析、规范化、比较；
2. PEP 440 version specifier 的解析与筛选；
3. 稳定、可诊断的错误类型。

## 结构

- `version.mbt`：`Version`、`LocalPart`、`VersionError`、解析器、规范化、
  `Eq`/`Compare`/`Show` 实现；
- `specifier.mbt`：`SpecifierOp`、`Specifier`、`SpecifierSet`、操作符匹配、
  通配符、compatible release、预发布规则；
- `*_test.mbt`：官方样例、错误拒绝、比较边例、specifier 操作符、
  预发布规则、生成式比较属性测试。

## 版本解析策略

解析器是一个按 UTF-16 偏移移动的 ASCII 游标，不引入正则依赖：

1. 去掉首尾 ASCII 空白，可选 `v` 前缀；
2. 尝试解析 epoch：数字后若为 `!` 则是 epoch，否则作为首个 release segment；
3. release 仅接受 `.` 分隔的数字段；
4. 后缀语法顺序为可选 `pre`、可选 `post`、可选 `dev`；同段重复或顺序错误即拒绝；
5. `+` 后解析 local version；local 段仅允许 ASCII 字母数字，并以
   `-`、`_`、`.` 分隔；
6. 所有整数通过 `BigInt` 解析，避免组件溢出。

## 规范化策略

`Version::to_string` 输出公开规范化形式：

- 数字组件去掉前导零；
- release 段数量保留：`1.0` -> `1.0`，`1.0.0` -> `1.0.0`；
- pre 拼写统一为 `a`/`b`/`rc`，post 统一为 `.post`，dev 统一为 `.dev`；
- `-`/`_` 在合法位置统一为规范分隔；
- local 段小写，纯数字段去掉前导零；
- `epoch` 为 0 时省略。

该形式与 `packaging.version.Version.__str__` 的公开形式一致；
不等于 `packaging.utils.canonicalize_version` 的“键形式”（后者会进一步
去掉 release 尾部零）。

## 比较策略

比较键顺序：

1. epoch；
2. release（短数组补零）；
3. pre：只有 dev、没有 pre/post 时低于 alpha；实际 pre 比较 `a < b < rc` 和数字；其余无 pre 高于实际 pre；
4. post：存在 post 的版本大于无 post；再比较 post 数字；
5. dev：存在 dev 的版本小于无 dev；再比较 dev 数字；
6. local：逐段比较；纯数字段按整数比较，文本段按小写 ASCII 比较；
   数字段大于文本段；前缀相同时段数更少者更小。

## Specifier 策略

- 每个 `SpecifierSet` 是若干 `Specifier` 的 AND 组合；
- `==`/`!=` 支持 `.*` 通配后缀；通配匹配 epoch + release 前缀；
- `==` 在目标无 local 时忽略候选 local，否则比较完整键；
- `~=` 下界含、上界不含；上界由倒数第二个 release 段加 1 构成；
- `===` 比较已解析候选的规范化字符串，不区分大小写；不提供 legacy 字符串候选接口；
- `<` 对边界 release 的 pre/dev 采用 PEP 440 排除规则；
- `>` 排除边界版本本身的 post；有序匹配忽略候选 local，有序边界禁止 local；
- `contains` 默认允许满足约束的单个预发布候选，符合 packaging 26.3 的单候选回退策略；
- `filter` 保持输入顺序：自动模式优先正式版，无匹配正式版才回退预发布；显式预发布边界允许预发布；
- 两个接口均允许 `prereleases=Some(true/false)` 覆盖自动策略。不排序、不求解。

## 边界

- 不做 pip、联网、下载、安装；
- 不做完整依赖求解和候选生成；
- 不解析包名、extras、环境标记、平台标签；
- 不提供 SemVer 兼容；
- local 段仅允许 ASCII 字母数字；
- 错误信息只包含稳定代码和 UTF-16 偏移，不回显敏感环境数据。

## 验证

`moon test` 覆盖官方规范化样例、非法输入、比较边例、各操作符、
预发布规则、通配符、`~=` 以及固定合法版本集上的反自反/反对称/传递性。
CI 在 wasm、wasm-gc、js、native 四目标执行 `fmt/check/build/test/run`。

JS 作业额外使用 Python packaging 26.3 独立比对 2050 项排序和约束结果。
版本固定是因为 packaging 26 修改了单候选预发布默认行为；测试不是全规范合规证明。
