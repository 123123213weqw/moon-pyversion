# 跨制品包审计场景

## 场景

在不联网、不下载和不读取宿主环境的前提下，判断一项 Python 依赖能否按给定锁文件，
从给定包索引中选择出与目标环境一致且带 sha256 的文件。

`examples/audit` 实际串联以下输入：

- PEP 508：`Flask==0.12.5`；
- 一份真实 PyPI wheel 的 PEP 658 `METADATA` sidecar（Flask 0.12.5）；
- 可审查的 PEP 691 JSON 索引，其中一个候选被标记为 yanked；
- 可审查的 PEP 751 `pylock.toml`，锁定 Flask 0.12.5；
- 调用方传入的 CPython 3.11.9、Linux 环境和 `py3-none-any` 标签。

真实 PyPI `METADATA` 保存在 `fixtures/metadata_corpus.mbt`，生成来源与抓取方法见
`tools/fetch_metadata_corpus.py`。索引和锁文件是为验收边界编写的确定性场景输入，
不冒充线上请求或生产锁文件。

## 复现

```sh
moon test --target js --deny-warn
moon run examples/audit --target js
```

预期关键结果：

```text
project: flask
disposition: ready
metadata: Flask 0.12.5
index: Flask, files=2, ignored=0, yanked=1
candidates: 1
selected: Flask-0.12.5-py3-none-any.whl
lock-versions: 0.12.5
issues: none
```

CI 在 wasm、wasm-gc、js、native 四后端运行同一示例，并在同一 Linux runner 上逐字节
比较报告。跨 Windows 与 Unix 时，native C 运行时的 CRLF/LF 差异不属于语义差异。

## 验收边界

只有以下条件同时满足才返回 `Ready`：需求对目标环境适用；元数据和索引名称一致；
元数据、锁文件与候选均支持目标 Python；目标环境被锁文件覆盖；恰有一个适用锁条目；
最佳候选与锁定版本、元数据版本一致；最终文件带 sha256。

缺少候选、名称漂移、版本漂移、锁条目歧义或缺少 sha256 时返回 `Blocked` 和稳定问题码。
需求标记排除当前环境时返回 `NotRequired`。解析错误沿用各格式已有的稳定错误类型。

该 API 不联网、不验证远端文件内容、不计算宿主平台标签、不做完整依赖求解，也不判断包的
安全性。sha256 在这里只检查索引是否声明；下载后的内容校验仍由上层工具负责。

## 源码体量口径

执行 `python -B tools/source_metrics.py` 可复核体量。脚本将根目录生产 MoonBit、测试、
示例、生成 fixture 和 Python 验证工具分开统计，避免把测试或生成语料当作核心源码。
