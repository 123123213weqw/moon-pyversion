# 双包离线镜像审计场景

## 输入与目标

`examples/bundle-audit` 使用仓库中真实 PyPI wheel 的 Flask 0.12.5、Jinja2 2.10.1
PEP 658 `METADATA`，以及这两个项目的真实 PEP 691 索引响应。示例锁文件是为验证
编写的确定性输入；其中 wheel 文件名及 sha256 声明取自上述索引，URL 是示例值，
不声称它是独立工具生成的生产锁文件。

目标为 CPython 3.11.9 / Linux，调用方显式传入 `py3-none-any` 标签。两项需求是
`Flask==0.12.5` 和 `Jinja2>=2.4`；索引包含比锁定版本更新的候选，以验证库不会
把“索引最新”误作“锁定目标”。此场景仅审计这两项显式输入，不检查 Flask 的全部
传递依赖，因此不是完整依赖求解或可安装性证明。

## 复现与验收

```sh
moon test --target js --deny-warn
moon run examples/bundle-audit --target js
```

报告关键结果：`bundle: 2 package(s), ready=2, blocked=0, not-required=0`；分别选择
`Flask-0.12.5-py2.py3-none-any.whl` 与 `Jinja2-2.10.1-py2.py3-none-any.whl`，两项
`issues: none`。四后端 CI 重跑该示例并比较报告。

负向单测还验证：锁定文件名缺失、索引与锁的 sha256 不一致、重复项目输入、宣称完整
覆盖但遗漏锁条目时返回 `Blocked` 和稳定问题码。sha256 只比较双方声明；库不下载
文件，也不计算文件内容摘要。完整覆盖选项仅要求每个适用锁条目有对应输入，不保证
所有传递依赖已解析。
