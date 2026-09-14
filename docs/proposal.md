# Moon PyVersion 项目申报书（技术事实稿）

## 一、项目与仓库

- **项目名称：** Moon PyVersion — Python 打包元数据工具库
- **GitHub：** https://github.com/123123213weqw/moon-pyversion
- **MoonBit 模块：** `123123213weqw/moon_pyversion`
- **方向：** 语言与开发工具 / 软件供应链基础库
- **许可证：** Apache-2.0

## 二、问题与项目定位

MoonBit 生态已有 SemVer 与依赖求解工具，但 Python 包使用 PEP 440、PEP 508、core
metadata、PEP 691 索引和 PEP 751 锁文件；epoch、pre/post/dev/local、环境标记、
`Requires-Python` 和平台标签均不能直接按 SemVer 处理。本项目提供纯 MoonBit、零第三方依赖
的解析与审计能力，让离线镜像、依赖检查和升级评估工具复用同一套确定规则。

## 三、已实现的核心能力

项目已实现 PEP 440 版本/约束、PEP 503 名称、PEP 427/625 文件名、PEP 508 需求与环境
标记、PEP 639 许可证、TOML 1.0、core metadata、PEP 691 索引、PEP 751 锁文件及候选
筛选。0.2.0 新增 `audit_package` 高层入口，把需求、真实元数据、索引、锁文件和明确的目标
环境合并为一次可审计决策，检查名称、Python 版本、环境、锁定版本、候选版本和 sha256，
返回 `Ready`、`Blocked` 或 `NotRequired` 及稳定问题码。

按 `tools/source_metrics.py` 的透明口径，根目录生产 MoonBit 为 **8,976 行**，另有 6,605 行
MoonBit 测试；该口径排除示例、生成 fixture 和 Python 工具，不把生成语料计作核心源码。

## 四、实际集成场景与验证

`examples/audit` 使用真实 PyPI wheel 的 Flask 0.12.5 PEP 658 `METADATA`，配合可审查的
PEP 691 索引、PEP 751 锁文件和 CPython 3.11/Linux 目标环境，实际完成“需求 → 元数据 →
锁定版本 → 可安装文件”的端到端审计。结果为 `Ready`，排除一项 yanked 候选，最终选择
`Flask-0.12.5-py3-none-any.whl`，且版本与锁文件、元数据一致并声明 sha256。

仓库另有真实 PyPI 语料差分实验：固定 `packaging==26.3`，对版本、约束、需求、元数据和
文件名逐条比对；TOML 对照 `tomli`。故意注入缺陷的 mutation probe 用于证明语料能够失败。
所有 MoonBit 测试、三个集成示例及报告一致性均纳入 wasm、wasm-gc、js、native CI。
场景输入、复现命令和验收条件见
[docs/audit-scenario.md](https://github.com/123123213weqw/moon-pyversion/blob/main/docs/audit-scenario.md)。

## 五、验收边界与生态差异

`Ready` 要求需求适用、制品名称一致、目标 Python 与环境满足、恰有一个适用锁条目、最佳候选
与元数据及锁定版本相同，并声明 sha256；任一条件不满足即给出稳定问题码。项目不联网、不下载、
不安装、不执行包，不计算宿主平台标签，不做完整依赖求解、冲突回溯或安全性判断。sha256 只检查
索引声明，下载后的内容校验由上层完成。

与 SemVer 库的差异是遵循 Python packaging 语义；与 `python123-ops/moondepsolve` 的差异是
提供解析、元数据和候选审计材料而不搜索完整依赖解。行为参考 PyPA 规范及 `pypa/packaging`
（Apache-2.0/BSD-2-Clause），未复制其源码，仅在测试中作固定版本黑盒对照。

## 六、交付与后续规划

交付物包括生产源码、测试、四后端 CI、真实语料、差分与 mutation 工具、基础/元数据/候选/
跨制品审计示例、设计和来源文档。MoonCakes 0.1.0 已发布；包含完整扩展与审计入口的 0.2.0
将在本轮验证后发布并做独立下载安装测试。

后续计划：增加调用方可注入的平台标签生成器；用独立第三方工具生成真实 `pylock.toml` 语料；
增加升级候选报告；逐条收敛已登记的 PEP 751 分歧。规划内容不作为当前已完成成果申报。

> 参赛者提交前须根据本人实际工作与理解核实本稿；赛事要求由本人撰写的部分不能由技术事实稿替代。
