# 申报前技术事实清单

> 本文件不是申报书。提交前由参赛者逐项核实，并确认最终申报文字符合本人实际工作与理解。

## 项目事实

- 项目：Moon PyVersion — Python 打包元数据工具库；
- 仓库：https://github.com/123123213weqw/moon-pyversion；
- MoonCakes：`123123213weqw/moon_pyversion`；仓库版本 0.2.0；
- 许可证：Apache-2.0；运行依赖仅 `moonbitlang/core`；
- 生产代码口径：`python -B tools/source_metrics.py`，不把测试、示例或生成 fixture 算作核心源码。

## 当前能力

- PEP 440、503、508、639、691、751，PEP 427/625，TOML 1.0 与 core metadata；
- `resolve_candidates` 完成候选过滤与确定排序；`upgrade_shortlist` 给出升级候选
  短名单与逐条拒绝原因；
- `audit_package` 统一检查需求、元数据、索引、锁文件和目标环境；
- 明确不联网、不下载、不安装、不做完整依赖求解或安全性判断。

## 验证事实

- 293 个 MoonBit 测试块；CI 覆盖 wasm、wasm-gc、js、native；
- `examples/metadata-check`、`examples/resolve`、`examples/audit`、
  `examples/upgrade-check` 为四个端到端场景；
- audit 场景使用真实 PyPI Flask 0.12.5 `METADATA`，索引和锁为确定性验收输入；
- 独立差分实验：122 640 条记录对照 CPython packaging 26.3，0 不一致；PEP 751 的
  锁文件语料含 6 份 `uv` 写出的真实锁文件，PEP 425 标签语料 62 组参数；声明分歧
  1 + 6 条；变异探针 43 处全部检出；
- 差分语料、oracle 版本、声明分歧与 mutation probe 以最新 CI 输出为准；
- 0.2.0 发布后必须从注册表独立下载安装验证，不能用 GitHub CI 代替。

## 提交前仍需本人确认

- 申报书是否准确反映本人实际贡献与理解；
- 最新提交 SHA、提交总数、作者归属和 CI 链接；
- MoonCakes 0.2.0 是否已发布且未 yanked；
- 赛事表格是否附上最新 Markdown，而非旧版本。
