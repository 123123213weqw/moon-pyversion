# Moon PyVersion 项目申报书（技术事实稿）

> 本稿按仓库可复现结果整理。赛事要求本人撰写和理解的内容，须由申报人亲自核实、改写后提交。

## 一、项目与方向

- 名称：Moon PyVersion——Python 打包元数据工具库
- GitHub：https://github.com/123123213weqw/moon-pyversion
- MoonBit 模块：`123123213weqw/moon_pyversion`；Apache-2.0；运行依赖仅 `moonbitlang/core`
- 方向：开发工具与软件供应链基础库，可供离线镜像、依赖检查和升级评估工具复用

## 二、简介与核心功能

Python 包版本有 epoch、预发布、post/dev/local 等语义，不能用 SemVer 直接代替。本项目用
纯 MoonBit 实现 PEP 440 版本与区间、PEP 508 需求和环境标记、分发文件名、PEP 425
平台标签、TOML、core metadata、PEP 691 索引及 PEP 751 锁文件的读取与判定。
`resolve_candidates` 给出候选与拒绝原因，`upgrade_shortlist` 给出待测升级短名单；
`audit_package` / `audit_bundle` 将需求、元数据、索引、锁文件和明确目标环境串成单包或
多包审计，选择锁定版本并核对文件名及双方 sha256 声明，返回稳定问题码。

## 三、场景与实际测试

1. **依赖清单检查：** `examples/metadata-check` 读取真实 PyPI 元数据和锁文件，报告越界、
   不适用、未锁定和无法解析的需求；Flask 0.12.5 的 Werkzeug 约束冲突会被检出。
2. **离线索引筛选：** `examples/resolve` 按名称、版本、`Requires-Python`、yank 状态与平台
   标签筛选 wheel，并解释每个被拒文件的首条规则。
3. **镜像与锁文件审计：** `examples/bundle-audit` 使用真实 PyPI 的 Flask 0.12.5 与
   Jinja2 2.10.1 元数据、真实索引响应及明确标注为场景输入的锁文件。两包均返回
   `Ready`；即使索引含更新候选，也选择锁定文件。负向测试覆盖摘要不一致、锁文件缺项、
   重复项目及锁条目未审计。复现步骤见 `docs/bundle-audit-scenario.md`。
4. **升级评估：** `examples/upgrade-check` 输出按最小步长排序的待测版本及逐项拒绝码；
   它只作版本筛选，不宣称升级安全。

## 四、技术路线、交付与验收边界

规则由手写游标和类型化模型实现；解释器、ABI、平台、标记环境均由调用方传入，不探测宿主。
当前根目录生产 MoonBit **9,984 行**、测试 **7,460 行 / 300 个测试块**，口径由
`tools/source_metrics.py` 复核，排除示例、生成语料及 Python 工具。四后端测试通过；
122,640 条差分记录对照固定的 `packaging==26.3` 为 0 不一致，43 处故障注入均被检出。
交付源码、五个场景程序、CI、真实语料、设计与验证文档。

项目不联网、不下载、不安装、不执行 Python 包，不计算实际文件摘要，不做完整依赖求解、
冲突回溯、构建前端或安全判断。`Ready` 仅表示**已提供材料**之间的版本、目标环境、
文件名和摘要声明一致，不证明全部传递依赖可安装。MoonCakes **0.2.0 已正式发布，
并在独立模块下载安装、调用审计接口验证**；归档 SHA-256 与注册表记录一致，
复现过程见 `docs/release-verification.md`。

## 五、原创、生态差异与后续计划

项目为独立 MoonBit 实现，参考 PyPA 规范；`pypa/packaging`（Apache-2.0 / BSD-2-Clause）
只用作固定版本黑盒对照，未复制源码。与 SemVer 库的差异是 Python 打包语义；与
`python123-ops/moondepsolve` 的差异是提供输入解析与单点审计，不做搜索和回溯。
后续拟补充真实第三方锁文件与更多跨项目审计样本、实际文件内容校验的上层适配器；
这些计划不计入当前成果。

## 六、本人理解（申报人填写）

请本人用自己的话说明：为什么锁定版本不能被索引最新版本替代；为什么环境由调用方注入；
为何只比较 sha256 声明、不能称作文件已校验。本节不能由技术事实稿冒充个人说明。
