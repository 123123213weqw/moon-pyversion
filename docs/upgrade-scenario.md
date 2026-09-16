# 升级候选评估场景

## 场景

输入一个当前版本、一个目标版本区间、一个预发布策略、一个目标 Python 版本和一份候选版本
列表，回答其中哪些版本值得跑一次测试。库只决定版本这一部分，其余留在调用方。

`examples/upgrade-check` 串联 8 组输入，覆盖策略、区间边界和拒绝原因的组合：

- 只允许补丁与次版本升级（目标区间 `>=1.2.3,<2.0`）；
- 上下界都存在的窗口（`>=1.5,<1.8`）；
- 预发布策略的三种取值（`auto`、`any`、`none`）；
- `Requires-Python` 收窄候选；
- 全部规则同时出现；
- 没有目标区间（此时策略不参与，预发布直接保留）。

裁决规则按固定顺序执行，**第一条命中**的就是报告打印的原因：`unparsable`、`same`、
`downgrade`、`out-of-range`、`prerelease`、`requires-python`；都不命中的进入短名单。短名单
升序排列，最小步长在前；同一版本的两种拼写保留为两条记录，顺序稳定。被拒候选保持调用方
给出的顺序。

预发布策略经由**区间**起作用：`auto` 只在区间内的其他候选都无法入选时才放行预发布，而
"其他候选"指比当前版本新且在区间内的那些；没有目标区间时不存在过滤，因此显式禁用预发布
也没有作用对象。这与 `SpecifierSet::filter` 的行为一致，两侧都由语料钉住。

## 复现

```sh
moon test --target js --deny-warn
moon run examples/upgrade-check --target js
```

预期关键结果（节选）：

```text
== everything at once
   current 1.26.0; target >=1.26,<2.0; prereleases auto; CPython 3.11
   8 candidate(s): 2 in the shortlist, 6 dropped
   shortlist, smallest step first: 1.26.4 1.27.0
   dropped 1.25.2: downgrade
   dropped 1.26.0: same
   dropped not-a-version: unparsable
   dropped 1.27.0rc1: prerelease
   dropped 2.0.0: out-of-range
   dropped 1.28.0: requires-python
```

CI 在 wasm、wasm-gc、js、native 四个后端运行同一示例，并逐字节比较报告（md5
`4339ad2e4afabe2d11c23f76665dd192`）。

## 验收边界

短名单只表示"比当前版本新、落在目标区间内、且通过预发布与 `Requires-Python` 两项检查"。
报告把这一点打印在输出里，并显式列出它不检查的内容：API 与行为兼容性、依赖可解性、安全
公告、构建与测试结果、发布说明。进入短名单是测试候选，不是升级建议；不在短名单里也不表示
该版本有问题。

无法判定的输入明确报告而不是给一个空短名单：当前版本不可解析（含空字符串）报
`UNPARSABLE_CURRENT`，目标区间不可解析报 `BAD_TARGET`。这两个码属于**报告这一层**——
示例的输入是文本，所以它自己解析并打印这两个码；库这一层要求调用方先交出 `Version` 与
`SpecifierSet`，解析失败沿用各格式已有的稳定错误类型。

`Requires-Python` 无法解析时按忽略处理而不是拒绝，与 pip 和本库 `index.mbt` 的解析器一致。

## 语料与测试

`fixtures/upgrade_corpus.mbt` 收录 51 条用例，另有 3 条不可判定输入；每条用例的短名单与
"每个被拒候选的原因"都由 PyPA `packaging` 26.3 给出，两侧必须同时一致，因此因为错误原因
拒绝一个候选也会失败，而不是只看短名单是否相同。`upgrade_test.mbt` 覆盖同一批规则，其中
"预发布策略只能通过区间起作用"和"等于当前版本不算升级"两条各配一处变异探针。

## 源码体量口径

`python -B tools/source_metrics.py` 的分组统计把生产 MoonBit、测试、示例、生成 fixture 和
Python 验证工具分开，避免把测试或生成语料当作核心源码。
