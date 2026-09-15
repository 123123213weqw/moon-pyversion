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

按 `tools/source_metrics.py` 的透明口径，根目录生产 MoonBit 为 **9,042 行**，另有 6,675 行
MoonBit 测试（259 个测试块，四个后端各自全通过）；该口径排除示例、生成 fixture 和 Python
工具，不把生成语料计作核心源码。`python -B tools/source_metrics.py` 会在仓库根目录打印
这张分组表，口径本身写在输出里而不是写在文档里。

## 四、实际集成场景与验证

`examples/audit` 使用真实 PyPI wheel 的 Flask 0.12.5 PEP 658 `METADATA`，配合可审查的
PEP 691 索引、PEP 751 锁文件和 CPython 3.11/Linux 目标环境，实际完成“需求 → 元数据 →
锁定版本 → 可安装文件”的端到端审计。结果为 `Ready`，排除一项 yanked 候选，最终选择
`Flask-0.12.5-py3-none-any.whl`，且版本与锁文件、元数据一致并声明 sha256。

仓库另有真实 PyPI 语料差分实验：**122 516 条**确定性记录逐条回放给 CPython
`packaging==26.3`，对版本、约束、需求、元数据和文件名逐条比对，**0 不一致**；TOML 对照
`tomli` 2.4.1。故意注入缺陷的 mutation probe（**36 处**，覆盖 M0–M11 的行为）用于证明语料
能够失败——36/36 全部被检出，探针默认拒绝在改过的工作树上运行。"0 不一致"只有在对照能失败
的前提下才有意义，这一层结论写在各层证据旁边，而不是单独当结论。
所有 MoonBit 测试、三个集成示例及报告一致性均纳入 wasm、wasm-gc、js、native CI。
场景输入、复现命令和验收条件见
[docs/audit-scenario.md](https://github.com/123123213weqw/moon-pyversion/blob/main/docs/audit-scenario.md)。

PEP 751 这一层要单独说清楚：`packaging` 没有 `pylock.toml` 读取实现，因此锁文件语料的
裁决与投影是本仓库按规范正文另写的一份读法，抓不出"两份读法同时读错同一段规范"。这一轮
为此补了两件事：一是把**6 份由 `uv 0.11.32` 写出的真实 `pylock.toml`**（flask / requests /
numpy / django / httpx / cattrs，50 个包，真实索引 URL 与 sha256，最长 77 KB）按输入纳入
语料，这是锁文件语料里**唯一不由本仓库生成**的文档；二是把库对规范的**分歧从 7 条收敛到
1 条**——原先 6 条是库比规范松（`created-by` 可缺可空、文件记录可无 `hashes`、`upload-time`
不校验 UTC、源树旁的冗余 `version`、文件列表条目强制要求 `version`、未实现次版本的
`lock-version` 直接拒绝），逐条对着规范的 `Required?` 行重读后全部收紧，每条都另配一条
"除此之外完全合法"的普通样例把它钉住。`uv` 只写不读、不给出裁决，所以这 6 份补的是**输入的
独立性**而不是第二份读法，这一点不写强；库在 6 条规则**收紧之后**仍然接受全部 6 份，是"收紧
没有牺牲真实兼容性"的证据。收敛过程、被探针抓出的语料漏洞（一条同时带了 `version` 的互斥
样例等于什么都没钉住）与那 1 条保留的分歧，写在
[docs/experiment-results.md](https://github.com/123213213weqw/moon-pyversion/blob/main/docs/experiment-results.md)
的 6.9 / 6.10 与 `pylock_cases/divergences.txt` 里。

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

后续规划与它现在的证据状态（**未完成的不写进已完成能力**）：

1. `[已完成]` 用独立第三方工具生成真实 `pylock.toml` 语料：`uv 0.11.32` 的
   `uv export --format pylock.toml` 生成的 6 份锁文件已按输入入库（`pylock_cases/uv/`），
   来源与命令写在同目录的 `provenance.txt`，文件不再重新生成。**未完成的部分也要写**：
   `uv` 只写不读，因此"两份读法同时读错同一段规范"这个短板仍然存在，只是语料里第一次
   有了不是本仓库写的文档。
2. `[已完成]` 逐条收敛已登记的 PEP 751 分歧：7 条收敛到 1 条（见上），分歧数量只减不增，
   每减一条都由普通语料样例与一处变异探针钉住。保留的 1 条是库有意比规范**严**：规范对
   "支持主版本但不支持次版本"只说 SHOULD warn，而本库没有警告通道。
3. `[下一步]` 增加调用方可注入的平台标签生成器：标签目前只做匹配与排序，表由调用方按
   `sys_tags()` 顺序传入。展开接口要仍然可注入，宿主探测留在调用方——"库不读运行时环境"
   正是它能在四个后端给出逐字节相同结果的原因。
4. `[下一步]` 增加升级候选报告 `examples/upgrade-check`：读当前版本与候选版本列表，输出
   落在目标区间内的待测试短名单，并把"满足版本约束 ≠ 可以安全升级"做成报告里的显式声明。
5. `[待确认]` MoonCakes 0.2.0 发布与独立下载安装验证；发布状态以注册表实际记录为准，
   GitHub CI 绿灯不能替代。

规划内容不作为当前已完成成果申报。

> 参赛者提交前须根据本人实际工作与理解核实本稿；赛事要求由本人撰写的部分不能由技术事实稿替代。
