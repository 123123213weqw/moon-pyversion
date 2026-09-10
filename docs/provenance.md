# Moon PyVersion 来源与许可证说明

## 参考来源

- PEP 440：`https://peps.python.org/pep-0440/`（版本方案、规范化、比较）；
- Python Packaging User Guide 的 Version specifiers：
  `https://packaging.python.org/en/latest/specifications/version-specifiers/`；
- PyPA/pypa `packaging` 项目：`https://github.com/pypa/packaging`
  （用于核对公开行为，未复制其源码）。

## 许可证状态

- PEP 440 文本为 Python 社区规范，本仓库以其公开规则为参考；
- PyPA/pypa `packaging` 采用 Apache-2.0 或 BSD-2-Clause 双许可证；
- 本项目代码为独立 MoonBit 实现，不包含 `packaging` 源码，仅参考其
  文档化的公开行为；
- 本项目采用 Apache-2.0，见 `LICENSE`；
- `moon-json-repair` 的 `LICENSE` 仅作为 Apache-2.0 标准文本来源复制，
  功能未复制。

## 生态查重结论

在 MoonCakes 与 GitHub 上以 `moon pyversion`、`moonbit pep440`、
`moonbit python version` 等关键词做了工具辅助检索（选题时记录）。未发现同名或同功能
MoonBit 包。**搜索未命中不是绝对无同类**；可能存在未被索引或表述不同的
实现。已知相邻项目是 `mizchi/semver`，其目标是 Semantic Versioning，
本项目目标是 Python PEP 440，属于相邻功能而非替代。

## 与 mizchi/semver 的差异

- SemVer 要求 `MAJOR.MINOR.PATCH` 三段；PEP 440 允许任意段 release；
- SemVer 的 build metadata 不参与优先级；PEP 440 local version 参与排序；
- SemVer 的 prerelease 语法与排序固定；PEP 440 有 dev/pre/post 三类后缀；
- PEP 440 有 epoch、compatible release（`~=`）、任意相等（`===`）、
  版本通配（`==1.4.*`）；
- 约束语法不同：SemVer range 与 PEP 440 specifier 不可互换。

2026-09-10 增加 packaging 26.3 黑盒行为对照；未引入其运行时代码。
