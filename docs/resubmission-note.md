# 重新提交说明

以下内容可粘贴到报名表的“修改说明 / 重新提交备注”中；提交前请将“最新提交”和
“CI”替换为 GitHub 页面上实际显示的信息，并由参赛者本人核实。

> 根据初审意见，本次已基于最新 `main` 分支完成实质性扩展。项目不再仅限于
> PEP 440 版本解析：现已覆盖 PEP 508 需求与环境标记、core metadata、PEP 691
> 索引、PEP 751 锁文件、TOML、许可证与候选筛选，并新增 `audit_package` 高层入口，
> 将需求、元数据、索引、锁文件和目标运行环境串成一次可审计决策。
>
> 为避免代码量统计口径不一致，仓库新增 `tools/source_metrics.py`。按排除测试、示例、
> 生成 fixture 和 Python 工具的透明口径，当前根目录生产 MoonBit 为 9,494 行；另有
> 6,976 行 MoonBit 测试、277 个测试块。该结果可在仓库根目录直接复核。
>
> 本次同时增加实际集成场景：`examples/audit` 使用真实 PyPI Flask 0.12.5 的 PEP 658
> `METADATA`，结合 PEP 691 索引、PEP 751 锁文件和明确的 CPython 3.11/Linux 目标，
> 完成“需求 → 元数据 → 锁定版本 → 可安装文件”的端到端审计；场景会排除 yanked
> 候选，并校验名称、Python 版本、锁定版本、候选版本和 sha256 声明。验收输入、预期
> 输出和明确边界见 `docs/audit-scenario.md`。
>
> 可靠性方面，277 个测试覆盖 wasm、wasm-gc、js、native；真实语料差分共 122,589 条，
> 固定对照 `packaging==26.3`，并保留 mutation probe（41 处注入缺陷全部检出）证明测试能够发现故意注入的
> 缺陷；PEP 751 锁文件语料另含 6 份由 `uv` 写出的真实 `pylock.toml`。
> 申报书也已重新整理，明确区分已完成能力、验收边界和后续规划。
>
> 烦请以 GitHub 最新 `main` 分支重新审核。如先前“有效源码仅千行以内”的结论来自旧提交，
> 可运行 `python -B tools/source_metrics.py` 按上述公开口径复核。谢谢。

## 提交前核对

- GitHub 仓库：https://github.com/123123213weqw/moon-pyversion
- 申报书：`docs/proposal.md`
- 实际场景：`docs/audit-scenario.md`
- 源码口径：`python -B tools/source_metrics.py`
- 完整测试：以最新 GitHub Actions 绿色运行记录为准
- MoonCakes：提交时填写实际已发布版本，不要把待发布版本写成已发布
