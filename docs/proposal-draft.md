# Moon PyVersion 申报前人工核对单

> 不是提交用申报书；提交文档为 `docs/proposal.md`。赛事要求本人独立撰写的内容，
> 尤其“本人理解”，须由对应账号的参赛者亲自补充和确认。

- 项目与仓库：Moon PyVersion，https://github.com/123123213weqw/moon-pyversion。
- 当前生产 MoonBit：9,984 行 / 13 文件；测试 7,460 行 / 300 块。
  用 `python -B tools/source_metrics.py` 复核，不把示例或生成 fixture 算成核心源码。
- 已完成能力：PEP 440/508/425/691/751 等解析与选择、单包/多包跨制品审计、
  升级待测短名单；不联网、不安装、不做完整依赖求解或安全判断。
- 实际场景：`examples/metadata-check`、`resolve`、`audit`、`bundle-audit`、
  `upgrade-check`；真实输入与人工场景输入要明确区分。
- MoonCakes：0.2.0 已发布并独立下载安装、调用审计接口；校验和与注册表一致。
- 提交前确认：最新提交与 CI、作者归属、实际贡献、申报书 Markdown 和官方表格。
