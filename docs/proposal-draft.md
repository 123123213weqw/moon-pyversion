# Moon PyVersion — 人工申报准备清单

> 技术资料，不是可提交的项目申报书。请参赛者独立撰写一页 Markdown；
> 不能删掉提示后将本文件冒充本人撰写。无需 PDF。

- 名称 / 仓库：[Moon PyVersion](https://github.com/123123213weqw/moon-pyversion)。
- 方向 / 需求：开发工具基础库，在 MoonBit 中处理 Python 包版本，而非 SemVer。
- 核心：PEP 440 解析/规范化/排序；约束 AND、通配、compatible release；可控预发布策略及候选筛选。
- 路线：ASCII 游标 + BigInt 比较键；回归/属性测试；四目标 CI；packaging 26.3 独立行为对照。
- 不做：pip、联网下载安装、依赖求解、包名/环境标记/平台标签解析、任意 legacy 字符串候选。

## 场景事实（请本人结合实际使用者写完整）

1. 依赖清单审查 → 上层先提取版本约束 → 调用 contains 检查锁定版本 → 报告越界项；非法版本返回稳定错误，不解析整个依赖表达式。
2. 离线索引筛选 → 上层提供候选版本数组 → filter 按约束筛选 → 默认优先正式版，无可用正式版时回退预发布；可显式禁用预发布。
3. 升级候选评估 → 解析当前和候选版本 → 比较排序并筛选目标区间 → 输出待测试清单；不保证 API 兼容、安全性或依赖可解。

## 来源、差异与交付核对

独立 MoonBit 实现，Apache-2.0；规则参考 [PyPA 版本规范](https://packaging.python.org/en/latest/specifications/version-specifiers/)。
[packaging](https://github.com/pypa/packaging)（Apache-2.0/BSD-2-Clause 双许可）
为行为参考，未引入其源码。区别于 SemVer：epoch、任意段 release、pre/post/dev 和 local 排序。
详细来源见 [provenance](provenance.md)，不声称生态绝无同类。

已具备库、README、示例、测试、CI、许可证；发布状态需单独确认。
请本人补充动机、亲自完成的工作、方案理解与计划；尤其解释预发布策略和“满足约束不等于安全升级”。
按 [赛事核对表](submission-checklist.md) 检查后，由对应参赛者本人提交。
