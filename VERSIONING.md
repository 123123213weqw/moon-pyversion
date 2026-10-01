# 版本政策

## 承诺

- 遵循语义化版本（SemVer）：MAJOR 破坏兼容、MINOR 向后兼容新增、PATCH 修复。
- 公开面以 `pkg.generated.mbti` 为准并由 CI 比对，公开面变更必须体现在快照 diff。

## 兼容性细则

- **错误码集合只增不改**：`VersionError` 变体与 `diagnostic` 文本中的稳定问题码
  （如 `METADATA_SELECTION_MISMATCH`）是审计报告的机器接口；新增视为 MINOR，变更或
  移除视为 MAJOR。
- 解析结果的**规范化输出**（`Version::to_string`、`canonicalize_*`）在 MAJOR 之前
  逐字节稳定——下游会把它写进锁文件和审计记录。
- 判定语义跟随 PyPA 规范文本：当上游规范修订导致判定变化时，按 PATCH/MINOR 发布
  并在 CHANGELOG 注明对应的规范变更，差分语料同步更新。
- `packaging==26.3` 黑盒对照的差分记录是兼容性的回归下限：任何"0 不一致"的回退
  都会挡住 CI。

## 发布流程

四后端 + 差分矩阵全绿 → `moon publish --dry-run` → `moon publish` → 独立消费模块
`moon add` + 冒烟 → `docs/release-verification.md` 回填 → 打 `vX.Y.Z` 标签。
