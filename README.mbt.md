# Moon PyVersion

Pure MoonBit library for parsing, normalizing, comparing, and filtering
Python package versions and PEP 440 version specifiers. Zero third-party
package dependencies; it uses only `moonbitlang/core`.

## Consumer example

Once publication is confirmed, add `123123213weqw/moon_pyversion@0.1.0`,
then import it in your `moon.pkg`. For source-based use see the repository README.

```text
import {
  "123123213weqw/moon_pyversion" @pyversion,
}
```

```moonbit nocheck
///|
fn main {
  let v = try! @pyversion.Version::parse("v01.002-rc3+ABC_007")
  println(@pyversion.Version::to_string(v))
  let spec = try! @pyversion.SpecifierSet::parse(">=1.0, !=1.4.*, <2.0")
  let accepted = @pyversion.SpecifierSet::filter(
    [try! @pyversion.Version::parse("1.5")],
    spec,
  )
  println(accepted.length())
}
```

The source repository contains this working example in `examples/basic`.

## Public API

- `Version::parse(String) -> Version raise VersionError`
- `Version::normalize(String) -> String raise VersionError`
- `Version::to_string(Version) -> String`
- `Version::compare(Version, Version) -> Int`
- `SpecifierSet::parse(String) -> SpecifierSet raise VersionError`
- `SpecifierSet::contains(SpecifierSet, Version, prereleases? : Bool? = None) -> Bool`
- `SpecifierSet::filter(Array[Version], SpecifierSet, prereleases? : Bool? = None) -> Array[Version]`

`Version` implements `Eq`, `Compare`, and `Show`. Its `raw` field retains the
caller's original string. `to_string` returns a normalized public form:
leading zeroes are removed, pre/post/dev spellings are canonicalized
(`a`, `b`, `rc`, `.post`, `.dev`), separators `-` and `_` are normalized to
the canonical form, local segments are lowercased, and numeric local segments
lose their leading zeroes. Release segment count is preserved, so `1.0`
normalizes to `1.0` and `1.0.0` to `1.0.0`; they still compare equal.

Parsing supports epochs, `v` prefixes, leading/trailing ASCII whitespace,
pre-release aliases (`alpha`, `beta`, `c`, `pre`, `preview`), post-release
aliases (`post`, `rev`, `r`), dev releases, implicit numeric zeroes, implicit
post releases (`1.0-1`), and local versions. Invalid input raises a stable
`VersionError` with a code and a UTF-16 offset. Errors never echo passwords,
paths, or unrelated runtime data.

## Ordering and specifier contract

Comparison follows the PEP 440 key order: epoch, padded release segments,
pre-release phase and number, post-release, dev, then local segments.
A bare dev release has a pre-key below alpha; otherwise absent pre sorts
after pre. Absent post sorts before post; absent dev sorts after dev.
Local segments are compared segment by segment, numerically when both
segments are numeric and case-insensitively otherwise; a numeric segment
sorts greater than a textual segment.

`SpecifierSet` supports `==`, `!=`, `<`, `<=`, `>`, `>=`, `~=`, and `===`.
Wildcard suffixes are accepted only for `==` and `!=` and match by epoch plus
release prefix. Compatible release (`~=`) uses an inclusive lower bound and an
exclusive upper bound formed by incrementing the penultimate release segment.
Arbitrary equality (`===`) compares the parsed candidate's normalized spelling
case-insensitively; arbitrary legacy-string candidates are not supported.
Wildcard release prefixes use zero padding. Ordered constraints ignore candidate
local labels and reject local labels in the constraint itself.

Pre-release policy matches packaging 26.3: `contains` automatically permits a
matching prerelease because it has no alternatives; `filter` prefers matching
finals, falling back to prereleases if none exist. Explicit prerelease boundaries
opt in. Pass `prereleases=Some(false)` to exclude or `Some(true)` to allow them.
Operator-specific exclusions still apply: `<1.0` excludes `1.0a1` even when
prereleases are enabled; `>1.0` excludes `1.0.post1`. This is not a resolver
or a security assessment of upgrade candidates.

License: Apache-2.0. See `docs/design.md`, `docs/provenance.md`, and the
repository `README.md`.
