# Moon PyVersion

Pure MoonBit library for parsing, normalizing, comparing, and filtering
Python package versions and PEP 440 version specifiers. Zero third-party
package dependencies; it uses only `moonbitlang/core`.

## Consumer example

Once publication is confirmed, add `123123213weqw/moon_pyversion@0.2.0`,
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
- `canonicalize_name(String) -> String`
- `canonicalize_version(String, strip_trailing_zero? : Bool = true) -> String`
- `parse_wheel_filename(String) -> WheelFilename raise VersionError`
- `parse_sdist_filename(String) -> SdistFilename raise VersionError`
- `Requirement::parse`, `Marker::parse`, `Marker::evaluate`
- `canonicalize_license_expression` / `canonicalize_license_file`
- `Toml::parse` and `Metadata::parse`
- `SimpleIndex::parse`, `LocalIndex::scan`, `resolve_candidates`,
  `select_best`, `explain_rejection`
- `Pylock::parse`, `Pylock::is_applicable`, `Pylock::applicable_packages`
- `cpython_tags`, `generic_tags`, `pure_python_tags`, `compatible_tags`,
  `mac_platforms`, `tag_rank`
- `audit_package(...) -> PackageAudit raise`
- `upgrade_shortlist(...) -> UpgradePlan`, `UpgradePlan::versions`,
  `UpgradePlan::rejection_summary`, `UpgradeCandidate::parse`

Two functions are the high-level integration boundaries, and both are built out
of the pieces above rather than beside them.

`audit_package` joins one PEP 508 requirement, one real core-metadata document,
one PEP 691 index response and one PEP 751 lock for an explicitly supplied
target. It reports cross-document name, Python, environment, version and sha256
inconsistencies without downloading or executing a file, and returns `Ready`,
`Blocked` or `NotRequired` with stable issue codes. See `examples/audit` and
`docs/audit-scenario.md`.

`upgrade_shortlist` answers the version part of "which of these candidates is
worth a test run?": given the current version, a target range, a prerelease
policy, a target interpreter and a candidate list, it returns the shortlist in
ascending order (smallest step first) plus the rule that dropped every other
candidate -- `unparsable`, `same`, `downgrade`, `out-of-range`, `prerelease` or
`requires-python`, in that order, first match wins. The prerelease policy is
`SpecifierSet::filter`'s, so it reaches the candidates through the range; a
`requires-python` that does not parse is ignored rather than treated as a
rejection, which is what pip does. The shortlist says nothing about API
compatibility, dependency solvability or security, and the example prints that
sentence in its own output rather than leaving it in a comment. See
`examples/upgrade-check` and `docs/upgrade-scenario.md`.

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
post releases (`1.0-1`), and local versions. Each suffix label accepts a single
`-`, `_` or `.` separator on either side, so `1.0post1`, `1.0-post1`,
`1.0_post1`, `1.0a1-5` and `1.0a1post2dev3` all parse. Invalid input raises a stable
`VersionError` with a code and a UTF-16 offset. Errors never echo passwords,
paths, or unrelated runtime data.

## Ordering and specifier contract

Comparison follows the PEP 440 key order: epoch, padded release segments,
pre-release phase and number, post-release, dev, then local segments.
A bare dev release has a pre-key below alpha; otherwise absent pre sorts
after pre. Absent post sorts before post; absent dev sorts after dev.
Local segments are compared segment by segment: numerically when both segments
are numeric, and otherwise as lowercased byte strings (a numeric segment sorts
greater than a textual one).

`SpecifierSet` supports `==`, `!=`, `<`, `<=`, `>`, `>=`, `~=`, and `===`.
Wildcard suffixes are accepted only for `==` and `!=` and match by epoch plus
release prefix. Compatible release (`~=`) uses an inclusive lower bound and an
exclusive upper bound formed by incrementing the penultimate release segment.
Arbitrary equality (`===`) compares the parsed candidate's normalized spelling
case-insensitively; arbitrary legacy-string candidates are not supported, and the
operand follows packaging's restrictions (no whitespace, `;` or `)`). Whitespace
is allowed around a specifier but not inside its version operand.
Wildcard release prefixes use zero padding. Ordered constraints ignore candidate
local labels and reject local labels in the constraint itself.

Pre-release policy matches packaging 26.3: `contains` automatically permits a
matching prerelease because it has no alternatives; `filter` prefers matching
finals, falling back to prereleases if none exist. Explicit prerelease boundaries
opt in. Pass `prereleases=Some(false)` to exclude or `Some(true)` to allow them.
Operator-specific exclusions still apply: `<1.0` excludes `1.0a1` even when
prereleases are enabled; `>1.0` excludes `1.0.post1`. This is not a resolver
or a security assessment of upgrade candidates.

## Packaging metadata helpers

`canonicalize_name` implements PEP 503 key normalization (lowercase, collapse
runs of `-`, `_` and `.` into `-`; leading and trailing separators survive).
`canonicalize_version` implements PEP 625 in both forms: by default it strips
trailing zeros from the release segment, which is the form used as an index
lookup key (`1.0.0` -> `1`, `0.0` -> `0`), and with
`strip_trailing_zero=false` it only normalizes the spelling (`v1.2.3` -> `1.2.3`).
Invalid input is returned unaltered rather than raising, matching `packaging`.

`parse_wheel_filename` implements PEP 427 (extension, part count, project name
rules, optional build tag, compressed tag set expansion) and returns a
`WheelFilename` with a normalized name, the version, `(leading digits, rest)` or
`None`, and the expanded tags sorted by code point. `parse_sdist_filename`
implements PEP 625 for `.tar.gz` and `.zip`, splitting on the last dash.

Both order strings with `String::lexical_compare`, because MoonBit's default
`String` comparison orders by length first and would disagree with PEP 440.

## Runnable scenarios

Four programs in `examples/` join the pieces into end-to-end decisions, and each
one is checked byte for byte across the four backends in CI:

1. `examples/metadata-check` -- four real `METADATA` documents plus a
   `pylock.toml` and one target environment: which requirements are out of range,
   which do not apply here, which are not locked, which cannot be parsed. On the
   real data one document is rejected for declaring a `Metadata-Version` the
   specification never defined, and one requirement genuinely conflicts with the
   lock.
2. `examples/resolve` -- one PEP 691 index response, a target tag list and a
   wheelhouse directory: the yank policy, the first failing rule for every
   rejected file, and the chosen candidate.
3. `examples/audit` -- requirement + real Flask 0.12.5 metadata + index + lock +
   CPython 3.11/Linux target: `Ready`, with one yanked candidate excluded and a
   sha256 declared.
4. `examples/upgrade-check` -- the shortlist for eight sets of inputs, including
   one that trips every rule at once.

The library never reads a file, the network, the clock or the host: every
interpreter version, ABI, platform and environment is supplied by the caller, so
the same input produces the same answer on every backend and on every machine.

## Differential experiment

Agreement with CPython `packaging` is measured rather than asserted.
`examples/diff` emits a deterministic corpus of **122 640 records** in 26 kinds,
from curated lists, grammar-generated input, single-character mutations and real
data: 3000 version strings, 500 constraint strings, 600 real `Requires-Dist`
lines and 900 real distribution filenames from 97 PyPI packages, 239 real
`METADATA` documents, 97 real PEP 691 index responses, 215 lock-file records
(including six `pylock.toml` files written by `uv`), 83 TOML documents, 62 tag
argument tuples and 51 upgrade cases. Corpus content is identical across wasm,
wasm-gc, js and native after normalizing the host C runtime's CRLF convention;
raw and normalized hashes are both reported.

* `python -B tools/diff_packaging.py --oracle-version 26.3` replays every record
  against `packaging` 26.3 and reports differences by source, kind, mode and cause.
* `python -B tools/target_parity.py` fails if the backends diverge.
* `python -B tools/oracle_matrix.py --oracle python3` replays one captured corpus
  against several `packaging` releases.
* `python -B tools/mutation_probe.py` breaks the library on purpose and asserts the
  corpus notices; all 43 injected defects are detected.

Current results: 0 differences against the targeted `packaging` 26.3; 4492, 2754
and 844 differences against 24.2, 25.0 and 26.0 respectively, all attributable to
upstream behaviour changes (automatic prerelease admission, the `<`/`>` range
rewrite, the `~=` upper bound, the 26.3 filename and marker grammars, and the
26.1/26.3 selector APIs). See `docs/experiment.md` and
`docs/experiment-results.md`. "Zero differences" only means something when the
comparison can fail, so the corpus keeps 43 deliberate defects beside it: the
probe refuses to run on a modified tree, and every injection has to be noticed.

Not every record kind has an external reference. `packaging` covers versions,
specifiers, filenames, requirement lines, markers, licences and core metadata;
TOML is checked against `tomli`. PEP 691 indexes and PEP 751 locks have no
reference implementation, so those records are compared against a second reading
of the specification text written in this repository -- which cannot catch two
readings that are wrong in the same way. For locks, six real `uv` lock files add
independence of *input*, not a second reading: `uv` writes them and does not read
them. Declared divergences are registered per kind and asserted in both
directions rather than tolerated.

The experiment found seven real defects in the library (suffix separator
grammar, textual local-segment ordering, specifier operand restrictions, `Name`
and `Provides-Extra` trailing underscores, `Keywords` whitespace, and wheel tag
case normalization), plus six PEP 751 relaxations that reading the
specification's own `Required?` lines turned into fixes, and four defects in the
test infrastructure. One of them is worth repeating: every wheel filename in the
corpus spelled its tags in lower case, so the two sides never disagreed about
the spelling and the tag-case defect was invisible until the corpus was given
mixed-case filenames.

License: Apache-2.0. See `docs/design.md`, `docs/provenance.md`, and the
repository `README.md`.
