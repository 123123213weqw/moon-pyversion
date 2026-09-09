# 项目申报书草稿

> **AI 辅助草稿，提交前须由本人逐项核实并改写确认，不得冒充本人撰写。**

## 项目名称

Moon PyVersion

## GitHub 地址

https://github.com/123123213weqw/moon-pyversion

## 简介

Moon PyVersion 是一个纯 MoonBit 库，按 PEP 440 实现 Python 包版本与
version specifier 的解析、规范化、比较和筛选。它面向需要在 MoonBit
应用中判断 Python 包版本兼容性的场景，零第三方依赖，只使用
`moonbitlang/core`。

## 方向与通用性

方向为“开发者工具 / 软件供应链基础库”。库只处理版本与约束，不绑定
包名、平台标签或网络协议，因此可复用于依赖检查、索引筛选、升级评估等
不同上层工具。

## 预期使用场景

1. **依赖清单检查**：读取项目元数据中的 `Requires-Python` 或依赖版本
   区间，对锁定版本逐个调用 `contains`，快速找出越界项。
2. **离线包索引筛选**：在本地镜像索引中按 `>=1.0, !=1.4.*, <2.0` 过滤
   候选版本，减少后续下载与构建尝试。
3. **升级候选评估**：解析当前版本与目标区间，比较候选版本并筛掉
   pre-release 边界项，生成“安全升级候选”短名单。

## 核心功能

- `Version::parse` / `normalize` / `to_string` / `compare`；
- 支持 epoch、多段 release、dev/pre/post、local、`v` 前缀、implicit post；
- `SpecifierSet::parse` / `contains` / `filter`；
- 支持 `==`、`!=`、`<`、`<=`、`>`、`>=`、`~=`、`===` 与 `.*` 通配；
- 稳定 `VersionError` 和格式化诊断；
- 生成式比较属性测试与多目标 CI。

## 技术路线

先以 MoonBit 结构体和错误类型建立模型；再用 ASCII 游标实现 PEP 440
解析与规范化；用 BigInt 释放比较键实现确定性排序；最后实现 specifier
的 AND 语义、通配匹配、compatible release 和 pre-release 边界规则。
测试采用 PEP 440 官方样例表、错误输入、边例和固定版本集属性测试。

## 预计交付成果

- 本地完整 MoonBit 库与 `examples/basic`；
- `moon test` 覆盖核心路径；
- `README.md`、`README.mbt.md`、`docs/*.md`；
- `.github/workflows/ci.yml` 四目标验证；
- 12 个真实有效提交并推送至公开仓库；

## 明确不做范围

不做 pip、联网下载安装、完整依赖求解器、平台标签、包名规范化、SemVer
兼容或自动发布/安装流程。

## 原创 / 移植 / 参考来源与许可证

原创 MoonBit 实现；参考 PEP 440 规范与 PyPA/pypa `packaging` 的公开行为，
未复制其源码。项目采用 Apache-2.0；`packaging` 为 Apache-2.0 或 BSD-2-Clause
双许可证。

## 真实需求

MoonBit 生态已有 SemVer 工具，但处理 Python 包索引、锁文件和依赖元数据时
需要 PEP 440 语义；目前缺少零依赖的纯 MoonBit 版本判断库。

## 生态差异

与 `mizchi/semver` 相邻但不替代：SemVer 固定三段、build metadata 不参与
优先级；PEP 440 允许任意段、local 参与排序，并有 epoch、`~=`、`===` 和
`.*` 通配。

## 本人理解

我理解本项目解决的是“在 MoonBit 中可靠地判断 Python 包版本是否满足约束”，
而不是重新实现包管理器。核心价值是可嵌入、确定性强、错误稳定、边界清楚。
