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
- `utils.mbt`：PEP 503 名称规范化、PEP 625 版本键形式、PEP 427/625 文件名解析；
- `requirements.mbt`、`markers.mbt`：PEP 508 需求行与环境标记；
- `toml.mbt`：TOML 1.0 读取与规范重序列化（`pyproject.toml` / `pylock.toml`）；
- `licenses.mbt`：PEP 639 许可证表达式与许可证文件路径；
- `metadata.mbt`：核心元数据（PEP 566/621/639/643/685/753）；
- `index.mbt`：严格 JSON、PEP 691 索引响应、离线目录扫描与候选解析；
- `pylock.mbt`：`pylock.toml`（PEP 751）读取与校验；
- `*_test.mbt`：官方样例、错误拒绝、比较边例、specifier 操作符、
  预发布规则、生成式比较属性测试。

## 版本解析策略

解析器是一个按 UTF-16 偏移移动的 ASCII 游标，不引入正则依赖：

1. 去掉首尾 ASCII 空白，可选 `v` 前缀；
2. 尝试解析 epoch：数字后若为 `!` 则是 epoch，否则作为首个 release segment；
3. release 仅接受 `.` 分隔的数字段；
4. 后缀按固定的预先、发布后、开发顺序各尝试一次，每个标签接受
   `[-_.]?label[-_.]?number?`（`-N` 是 `.postN` 的另一种拼写）。只有当标签
   确实跟在分隔符之后时，该分隔符才被这一组消费，否则留给下一组；顺序错误
   或同段重复即拒绝；
5. `+` 后解析 local version；local 段仅允许 ASCII 字母数字，并以
   `-`、`_`、`.` 分隔；
6. 所有整数通过 `BigInt` 解析，避免组件溢出。

第 4 条是差分实验查出的：早期实现先无条件吃掉一个分隔符再匹配标签，于是
`1.0post1`、`1.0-post1`、`1.0a1post2dev3`、`1.0a1-5` 这类合法拼写全部被拒。

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
6. local：逐段比较；纯数字段按整数比较，文本段按小写字节序比较
   （用 `String::lexical_compare`，不能用 `String` 的默认比较，后者先比长度）；
   数字段大于文本段；前缀相同时段数更少者更小。

## Specifier 策略

- 每个 `SpecifierSet` 是若干 `Specifier` 的 AND 组合；
- `==`/`!=` 支持 `.*` 通配后缀；通配匹配 epoch + release 前缀；
- `==` 在目标无 local 时忽略候选 local，否则比较完整键；
- `~=` 下界含、上界不含；上界由倒数第二个 release 段加 1 构成；
- `===` 比较已解析候选的规范化字符串，不区分大小写；不提供 legacy 字符串候选接口；
- `<` 对边界 release 的 pre/dev 采用 PEP 440 排除规则（与 packaging 26.3 的
  区间实现对齐；26.0 及更早的实现更严格，见差分实验结果）；
- `>` 排除边界版本本身的 post；有序匹配忽略候选 local，有序边界禁止 local；
- `contains` 默认允许满足约束的单个预发布候选，符合 packaging 26.3 的单候选回退策略；
- `filter` 保持输入顺序：自动模式优先正式版，无匹配正式版才回退预发布；显式预发布边界允许预发布；
- 两个接口均允许 `prereleases=Some(true/false)` 覆盖自动策略。不排序、不求解；
- 约束内的 version 操作数不允许出现空白（packaging 的正则同样如此），
  `===` 的操作数按 packaging 的限制拒绝空白、`;` 和 `)`。

## 边界

- 不做 pip、联网、下载、安装；
- 不做完整依赖求解和冲突回溯（`resolve_candidates` 只在**一个**约束下排序候选）；
- 不计算平台标签：标签表由调用方按 `sys_tags()` 顺序传入，库只做匹配与排序；
- 不读运行时解释器环境：标记求值只接受调用方传入的环境表；
- 不提供 SemVer 兼容；
- local 段仅允许 ASCII 字母数字；
- 错误信息只包含稳定代码和偏移（JSON 层是 UTF-16 偏移），不回显敏感环境数据。

## 打包元数据辅助（`utils.mbt`）

与 `packaging.utils` 对齐的四项能力，语义均已用 `packaging 26.3` 核实：

- `canonicalize_name`：PEP 503。小写后把 `-`、`_`、`.` 的连续串折成一个 `-`；
  **首尾分隔符保留**（`-foo-` 仍是 `-foo-`），`--` 折成 `-`；
- `canonicalize_version`：PEP 625，**两种形式都提供**。默认去掉 release 尾部零
  （索引查找键，`1.0.0` -> `1`，且至少保留一段，`0.0` -> `0`）；传
  `strip_trailing_zero=false` 只做拼写规范化（`v1.2.3` -> `1.2.3`）。
  非法输入**原样返回而不报错**，与 packaging 一致；
- `parse_wheel_filename`：PEP 427。扩展名、连字符段数（4 或 5）、项目名
  （`[\w._]+`、非空、不含 `__`）、版本、可选 build 段（`(前导数字, 其余)`）、
  以及压缩标签集展开（`py2.py3-none-any` -> 2 个 tag）。标签输出为
  `interpreter-abi-platform` 字符串，按**码点**排序去重；
- `parse_sdist_filename`：PEP 625。扩展名限 `.tar.gz` / `.zip`，从**最后一个**
  连字符切分（PEP 440 版本不含连字符），项目名非空，名称规范化。

排序与比较一律用 `String::lexical_compare` 而不是 `String` 的默认比较：
后者先比长度，会与 PEP 440 / packaging 的码点序不一致。这一点在 local 段
比较和标签排序上各踩过一次，两次都由测试或差分语料抓出。

已知边界：名称规范化与 wheel 名称校验按 ASCII 实现；packaging 在这两处使用
Unicode 感知的正则。PEP 427 要求 wheel 文件名是转义后的 ASCII，因此实际输入
不受影响，差分语料也刻意不在这两类记录里放非 ASCII。

## 验证

`moon test` 覆盖官方规范化样例、非法输入、比较边例、各操作符、
预发布规则、通配符、`~=` 以及固定合法版本集上的反自反/反对称/传递性，
共 259 个测试块，在 wasm、wasm-gc、js、native 四目标验证。
CI 在四个目标执行 `fmt/check/build/test/run`。

另有独立差分实验：`examples/diff` 生成 122 516 条确定性记录（手工语料、
按 PEP 440 文法生成、单字符变异、真实 PyPI 元数据四种来源，加上 TOML 文档、
PEP 691 索引响应、核心元数据与 PEP 751 锁文件），逐条回放给 CPython
`packaging 26.3`；TOML 另有参考实现 `tomli`，PEP 691 与 PEP 751 则对照按规范
另写的第二份读法（后者没有现成实现可对照，见
[experiment-results.md](experiment-results.md) 6.9；语料里唯一不由本仓库生成
的输入是 6 份 `uv` 写出的真实 `pylock.toml`，而 `uv` 只写不读、不给裁决）。设计与数据见
[experiment.md](experiment.md)、[experiment-results.md](experiment-results.md)。

版本固定为 26.3 不是随手选的：`tools/oracle_matrix.py` 实测 24.2 有 4474 条、
25.0 有 2736 条、26.0 有 826 条差异，26.3 为 0 条，差异全部对应上游已发布的
行为变更。
差分实验证明的是"与 packaging 26.3 一致"，不是全规范合规证明。

三个场景各有可运行示例：`examples/metadata-check`（元数据与锁检查）、
`examples/resolve`（索引到候选文件）与 `examples/audit`（需求、真实元数据、索引、
锁文件和目标环境的统一审计）。CI 在同一 runner 上要求四后端逐字节一致；跨 Windows
与 Unix 复现时，验证工具仅规范化 CRLF/LF，并同时保留原始与规范化摘要。
