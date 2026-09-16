# Moon PyVersion 项目申报书

## 一、项目与仓库

- 项目名称：Moon PyVersion（Python 打包元数据工具库）
- 仓库地址：https://github.com/123123213weqw/moon-pyversion
- MoonBit 模块：`123123213weqw/moon_pyversion`，仓库版本 0.2.0，许可证 Apache-2.0；
  MoonCakes 上已发布 0.1.0，含本轮扩展的 0.2.0 尚未发布
- 方向：开发工具基础库，软件供应链；运行依赖只有 `moonbitlang/core`

## 二、简介与定位

用纯 MoonBit 实现的 Python 打包元数据处理库。库把 PEP 440 版本与版本区间、PEP 508 需求与
环境标记、PEP 427/625 分发文件名、PEP 425 平台标签、TOML 1.0、core metadata、PEP 691
包索引和 PEP 751 锁文件解析为确定的数据结构，并在此之上提供候选筛选和一次性的包审计。

Python 打包语义不能按 SemVer 处理：版本含 epoch、任意长度 release 段与 pre/post/dev/local
段，区间含 `~=` 兼容释放与可配置的预发布准入，平台适用性由标签集合决定。库不联网、不读
文件系统与时钟，解释器版本、ABI、平台和目标环境等宿主事实全部由调用方注入，因此同一份
规则可用于服务端、CI 与 wasm / JavaScript 目标，行为也能用确定性输入复现。

## 三、使用场景

四个场景都是可运行程序，报告在 wasm、wasm-gc、js、native 四个后端逐字节相同。

| 场景 | 输入 | 输出与实测结果 |
| --- | --- | --- |
| 依赖清单审查<br>`examples/metadata-check` | 4 份真实 PyPI wheel 的 `METADATA`、一份 `pylock.toml`、固定目标环境 | `ok`、`OUT OF RANGE`、`not applicable`、`not locked`、`UNPARSABLE` 与汇总；flask 0.12.5 检出真实冲突（锁里 werkzeug 2.0.0，要求 `<1.0,>=0.7`），requests 2.24.0 因 `Metadata-Version: 2.0` 不是规范版本被拒；4 份文档共 2 个问题 |
| 离线索引筛选<br>`resolve_candidates`、`examples/resolve` | 一份 PEP 691 索引响应、一组按优先级排列的目标标签、一个本地 wheelhouse 目录 | 按名称、区间、预发布策略、`Requires-Python`、yank 状态与标签过滤，输出顺序确定的候选表与每个被拒文件的首条失败规则；示例 11 个文件被拒 6 个 |
| 跨制品审计<br>`audit_package`、`examples/audit` | PEP 508 需求、真实 PyPI `METADATA`、PEP 691 索引响应、PEP 751 锁文件、目标环境 | `Ready`、`Blocked` 或 `NotRequired` 与稳定问题码；`Flask==0.12.5` 在 CPython 3.11.9 / Linux 上为 `Ready`，排除一个 yanked 候选，选中 `Flask-0.12.5-py3-none-any.whl`，版本与 sha256 声明一致 |
| 升级候选评估<br>`upgrade_shortlist`、`examples/upgrade-check` | 当前版本、目标区间、候选版本列表 | 待测短名单（升序，最小步长在前）与拒绝码 `unparsable`、`same`、`downgrade`、`out-of-range`、`prerelease`、`requires-python`；报告另列出它不检查的内容 |

审计场景的验收条件见 `docs/audit-scenario.md`，升级场景的输入与裁决见
`docs/upgrade-scenario.md`，各场景的端到端输出见 `docs/experiment-results.md`。

## 四、实现与交付

生产代码 9 778 行，分 13 个文件；另有测试 7 311 行（293 个块）、示例 4 288 行（7 个程序）
和生成语料 4 082 行。口径见 `tools/source_metrics.py`，生成语料不计入核心源码。

解析使用手写 ASCII 游标而非正则引擎，错误是可穷举的稳定错误类型，版本比较使用规范化比较
键。模块按规范划分：PEP 440 版本与区间，PEP 503 名称与 PEP 427/625 分发文件名，PEP 508
需求与环境标记（含 extra 规范化），PEP 639，TOML 1.0，core metadata，PEP 691 索引与离线
目录扫描，PEP 751 锁文件，PEP 425 标签，以及 `audit_package`、`upgrade_shortlist` 两个
高层入口。

交付物为库源码、测试、7 个示例、四后端 CI、生成语料与 Python 验证工具、设计与来源文档。

## 五、验证

| 手段 | 规模 | 结果 |
| --- | --- | --- |
| 单元与属性测试 | 293 个块 | 四后端全部通过 |
| 差分实验 | 122 640 条记录 | 逐条对照 `packaging==26.3`，0 不一致 |
| 多版本漂移 | 同上语料 × 4 版本 | 24.2 差 4 492、25.0 差 2 754、26.0 差 844、26.3 差 0 |
| 变异探针 | 43 处故意缺陷 | 43/43 被检出 |

语料含 97 个 PyPI 包的 3 000 个版本、500 条区间、600 条真实 `Requires-Dist` 行、900 个真实
文件名，285 份元数据文档（239 份来自 PyPI）、118 份索引文档（97 份来自真实索引响应）、215 条
锁文件记录（含 6 份 `uv` 写出）、83 份 TOML 文档、62 组标签参数和 51 条升级用例；TOML
一侧对照 `tomli`。明细见 `docs/experiment-results.md`。

## 六、不做范围

不联网、不下载、不安装、不执行包；不探测宿主环境，解释器版本、ABI 与运行中 libc 由调用方
注入；不做完整依赖求解、冲突回溯和安全判断；sha256 只检查索引声明；不实现 PEP 517/518
构建前端与 PEP 660 可编辑安装。

## 七、来源与生态差异

原创实现，Apache-2.0，未复制 `pypa/packaging` 源码；`packaging`（Apache-2.0 / BSD-2-Clause
双许可）只作为固定版本的测试期黑盒对照，行为依据 PyPA 规范正文与 TOML 1.0、RFC 8259、
RFC 822 风格头部，来源见 `docs/provenance.md`。与 SemVer 类库的差异是遵循 Python 打包语义；
与 `python123-ops/moondepsolve` 的差异是提供解析、元数据和候选审计材料，不搜索完整依赖解。
已知短板是 `packaging` 没有 `pylock.toml` 读取实现，锁文件语料的裁决是本仓库按规范正文另写
的一份读法；已登记的 7 条分歧收敛到 1 条，保留的 1 条是本库有意比规范严格。

## 八、本人理解

最关键的取舍是宿主事实全部由调用方注入：库一旦自己探测解释器或平台，行为就无法用固定输入
复现，差分对照也无从进行。其次是宁可严格也不静默宽容，与规范不一致处逐条登记为声明分歧，
数量只减不增。再者是通过测试本身不是结论：差分实验共查出 7 处真实缺陷，其中 wheel 标签
大小写未归一一处出自语料本身，因为语料里每个文件名都写小写，两侧对另一种拼写都不产生
输入，那条差异此前从未被触发。语料覆盖不到的地方必须另外说明。

> 数据以仓库当前提交为准；提交前核对最新提交 SHA 与 CI 结论，并在 MoonCakes 确认 0.2.0
> 已发布且未被 yank。
