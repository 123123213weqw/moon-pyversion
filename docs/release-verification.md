# 发布验证记录（MoonCakes）

本文件记录**从注册表独立下载并运行**已发布版本的实测过程与结果，用于替代「CI 绿灯」
这类间接证据。每一节都给出可重跑的命令和当时的原始输出。

以下第 1–5 节是 **2026-09-16 的 0.1.0 历史记录**，当时“0.2.0 尚未发布”的描述
只对该日期有效。**当前 0.2.0 的发布与独立安装验证在第 6 节。**

历史验证环境：`moon 0.1.20260904`（moonc v0.10.12），Linux x86_64，2026-09-16。

2026-09-20 复核：旧稿的 API 命令、部分示例输出及仓库字段误写为
`123213213weqw`（少一个 `1`），该地址实际返回 404。下文已更正为注册表实际账号
`123123213weqw`；当时正确 API 返回 0.1.0、未 yank，checksum 与原记录相同。

## 1. 已发布版本清单

公开注册表 API（任何联网机器都能查，不需要凭据）：

```text
$ curl -sS https://mooncakes.io/api/v0/modules/123123213weqw/moon_pyversion
{"module": "123123213weqw/moon_pyversion", "version": "0.1.0", "yanked": false,
 "yanked_reason": null, "metadata": {"name": "123123213weqw/moon_pyversion",
 "version": "0.1.0", "readme": "README.mbt.md", "license": "Apache-2.0",
 "checksum": "16379fadb3bfc7084d9e7a70b16a232dc0219d541a81ef5dfe0dc2451b6358fd",
 "created_at": "2026-09-10T14:51:57.925603+00:00", ...}}
```

`version` 是最新版本，即只有一个 0.1.0；`yanked` 为 false。本地注册表索引给出同一结论，
并说明「只有 0.1.0」不是「接口只返回最新版」——`moon update` 之后的
`~/.moon/registry/index/user/123123213weqw/moon_pyversion.index` 里，本模块只有**一条**记录：

```text
$ wc -l ~/.moon/registry/index/user/123123213weqw/moon_pyversion.index
1
$ cat ~/.moon/registry/index/user/123123213weqw/moon_pyversion.index
{"name": "123123213weqw/moon_pyversion", "version": "0.1.0", "readme": "README.mbt.md",
 "repository": "https://github.com/123123213weqw/moon-pyversion", "license": "Apache-2.0",
 "keywords": [...], "description": "...",
 "checksum": "16379fadb3bfc7084d9e7a70b16a232dc0219d541a81ef5dfe0dc2451b6358fd",
 "created_at": "2026-09-10T14:51:57.925603+00:00", "yanked": false, "yanked_reason": null}
```

结论：**0.1.0 已发布且未被 yank**；没有 0.2.0 的记录，即**本轮扩展所在的 0.2.0 尚未发布**。
（同作者的 `moon_proto` 在同一索引里有两行 `0.1.0` / `0.1.1`，说明多版本模块的记录格式相同，
「只有一行」不是文件格式问题。）

## 2. 依赖解析与下载

在一个临时模块里按名字添加依赖：

```text
$ mkdir -p /tmp/mcprobe && cd /tmp/mcprobe
$ printf 'name = "probe/mcprobe"\nversion = "0.1.0"\n' > moon.mod
$ moon update
Registry index updated successfully
$ moon add 123123213weqw/moon_pyversion
Symbols updated successfully
Downloading 123123213weqw/moon_pyversion@0.1.0
```

`@0.2.0` 无法解析（注册表里没有该版本）：

```text
$ moon add 123123213weqw/moon_pyversion@0.2.0
Error: Failed to resolve registry dependency `123123213weqw/moon_pyversion` for module
`probe/mcprobe`: module was not found in the registry
```

## 3. 下载物的完整性

下载缓存里的归档与索引记录的 `checksum` **逐字节对应**：

```text
$ sha256sum ~/.moon/registry/cache/123123213weqw/moon_pyversion/0.1.0.zip
16379fadb3bfc7084d9e7a70b16a232dc0219d541a81ef5dfe0dc2451b6358fd  .../0.1.0.zip
```

与第 1 节的 `checksum` 相同。归档 33 975 字节、23 个文件，内容是 **0.1.0 时期的树**：

```text
$ unzip -l .../0.1.0.zip
  1490  CHANGELOG.md                     2261  regression_test.mbt
  1809  docs/applicant-notes.md          8378  specifier.mbt
  4221  docs/design.md                   4207  specifier_test.mbt
  2205  docs/proposal-draft.md           1409  tools/check_packaging.py
  7415  docs/proposal.md                13432  version.mbt
  2162  docs/provenance.md               4618  version_test.mbt
  1886  docs/submission-checklist.md      380  moon.mod
  1414  examples/basic/main.mbt            72  moon.pkg
    90  examples/basic/moon.pkg          2678  properties_test.mbt
  1117  examples/oracle/main.mbt         4125  README.mbt.md
    90  examples/oracle/moon.pkg         5507  README.md
 11525  LICENSE
  82491  bytes, 23 files
```

也就是说，已发布的 0.1.0 只含 `version.mbt` 与 `specifier.mbt` 两个源文件——它是**扩宽之前**
的 PEP 440 版本/约束库，没有 `metadata.mbt`、`index.mbt`、`pylock.mbt`、`toml.mbt`、
`licenses.mbt`、`tags.mbt`、`upgrade.mbt` 与 `audit.mbt`。发布物是快照而不是工作树，
这一点用归档清单可以直接看到。

## 4. 安装后实际运行

在同一个临时模块里写一个使用已发布包的程序并运行：

```moonbit
fn main {
  let v = try! @pyversion.Version::parse("v01.002-rc3+ABC_007")
  println(@pyversion.Version::to_string(v))
  let spec = try! @pyversion.SpecifierSet::parse(">=1.0, !=1.4.*, <2.0")
  let kept = @pyversion.SpecifierSet::filter(
    [try! @pyversion.Version::parse("1.2"), try! @pyversion.Version::parse("1.4.1")],
    spec,
  )
  println(kept.length())
}
```

```text
$ moon run .
1.2rc3+abc.7
1
```

第一行是规范化结果（`v01.002-rc3+ABC_007` → `1.2rc3+abc.7`），第二行说明
`!=1.4.*` 把 `1.4.1` 排除、只留下 `1.2`。**下载、解析依赖、编译、运行四步都通过**，
不是只看下载成功。

## 5. 这次验证没有覆盖什么

- 只验证了 0.1.0。0.2.0 尚未发布，因此本轮新增的 `audit_package`、`tags.mbt` 与
  `upgrade_shortlist` **不在**这次下载验证范围内；发布 0.2.0 之后必须重跑第 2–4 节。
- 只在 Linux x86_64 上运行；没有验证 Windows、macOS 或 wasm/js 目标上的注册表安装。
- 注册表索引在首次 `moon add` 时可能尚未包含最新条目：本次就先遇到
  `Could not find the latest published version`，`moon update` 之后同一条命令成功。
  也就是说，**验证发布状态前必须先 `moon update`**，否则会得到假阴性。

## 6. 当前版本 0.2.0：发布及独立安装（2026-09-20）

账号 `123123213weqw`，从仓库 `ba8a383` 执行 `moon publish --frozen`：

```text
Running moon check ...
Check passed
validating packaged zip: ...123123213weqw-moon_pyversion-0.2.0.zip
running moon check on extracted package
Check passed
Server status: 200 OK
```

公开注册表 API `https://mooncakes.io/api/v0/modules/123123213weqw/moon_pyversion`
返回 `version: 0.2.0`、`latest_version: 0.2.0`、`yanked: false`，仓库字段为本项目地址，
`metadata.checksum` 为：

```text
212b53be9f908391c5f0044f338ca1ea32f8535f5050933d68ac856f2b682828
```

独立于项目仓库，在 D 盘新建临时模块 `probe/mcprobe`，运行：

```text
$ moon update
Registry index updated successfully
$ moon add 123123213weqw/moon_pyversion@0.2.0
Downloading 123123213weqw/moon_pyversion@0.2.0
$ sha256sum <registry-cache>/123123213weqw/moon_pyversion/0.2.0.zip
212b53be9f908391c5f0044f338ca1ea32f8535f5050933d68ac856f2b682828
```

下载包 1,171,933 字节；其 SHA-256 与公开注册表一致。消费者在 `moon.pkg` 中导入
`"123123213weqw/moon_pyversion" @pyversion`，运行以下两类调用：

- `Version::parse("v01.002-rc3+ABC_007")`；
- 新增的 `audit_package`，输入确定的 `demo-pkg==1.2` 元数据、索引、锁文件和
  CPython 3.11 / Linux / `py3-none-any` 环境，并调用 `PackageAudit::render()`。

`moon run cmd/main --target js` 的核心输出：

```text
1.2rc3+abc.7
project: demo-pkg
requirement: demo-pkg==1.2
disposition: ready
selected: demo_pkg-1.2-py3-none-any.whl
lock-versions: 1.2
issues: none
```

因此 0.2.0 不只是注册表条目存在：**下载、依赖解析、编译以及新版审计调用均已通过**。
此独立消费者使用确定的最小输入，不代替仓库中真实 PyPI 双包场景与四后端 CI；
也不证明实际 wheel 内容的摘要或完整传递依赖可安装。对应 GitHub CI：
`ba8a383` 的 [全部任务成功记录](https://github.com/123123213weqw/moon-pyversion/actions/runs/35520747149)。
