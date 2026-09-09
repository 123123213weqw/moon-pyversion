# Moon PyVersion

Pure MoonBit library for parsing, normalizing, comparing, and filtering
Python package versions and PEP 440 version specifiers. Zero third-party
package dependencies; it uses only `moonbitlang/core`.

## Consumer example

Add `123123213weqw/moon_pyversion@0.1.0`, then import it in your `moon.pkg`:

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
- `SpecifierSet::contains(SpecifierSet, Version) -> Bool`
- `SpecifierSet::filter(Array[Version], SpecifierSet) -> Array[Version]`

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
dev, pre-release phase and number, post-release, then local segments.
Absent dev/pre sort after present dev/pre; absent post sorts before present
post. Local segments are compared segment by segment, numerically when both
segments are numeric and case-insensitively otherwise; a numeric segment
sorts greater than a textual segment.

`SpecifierSet` supports `==`, `!=`, `<`, `<=`, `>`, `>=`, `~=`, and `===`.
Wildcard suffixes are accepted only for `==` and `!=` and match by epoch plus
release prefix. Compatible release (`~=`) uses an inclusive lower bound and an
exclusive upper bound formed by incrementing the penultimate release segment.
Arbitrary equality (`===`) compares the candidate's original raw string.

Pre-release filtering follows the PEP 440 boundary rule: a strict upper bound
rejects a pre/dev release of the boundary release, and `==` does not make a
final release match its pre-releases. Explicit pre/dev specifiers, prefix
wildcards, and `!=` keep their normal comparison behavior. This library is
not a dependency resolver.

License: Apache-2.0. See `docs/design.md`, `docs/provenance.md`, and the
repository `README.md`.