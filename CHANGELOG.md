# Changelog

## Unreleased — lock-aware audit and multi-project mirror scenario

- `audit_package` now selects a compatible file from the locked version before
  considering index order. The selected filename must be present in the lock,
  and the lock/index sha256 declarations must agree (hex case-insensitively).
- `audit_bundle` audits multiple explicit project inputs against one parsed
  lock and target, identifies duplicate project inputs and optionally checks
  coverage of applicable lock entries. It is not a transitive dependency solver.
- `examples/bundle-audit` joins real PyPI Flask/Jinja2 metadata and indexes with
  an explicit two-entry lock. The four-target CI runs and compares its report.
- Current effective production MoonBit: 9,984 lines; tests: 7,460 lines and
  300 blocks. Generated fixtures, examples and Python tools are reported
  separately by `tools/source_metrics.py`.

## Unreleased — M13: the upgrade shortlist (scenario 3)

### Added

- `upgrade.mbt` (284 lines) and `examples/upgrade-check` (268 lines). `upgrade_shortlist`
  answers the version part of "which of these candidates is worth a test run?": given a
  current version, a target range, a prerelease policy, a target interpreter and a list of
  candidates, it returns the shortlist in ascending order plus the rule that dropped every
  other candidate -- `unparsable`, `same`, `downgrade`, `out-of-range`, `prerelease` or
  `requires-python`, in that order, first match wins. A `requires-python` that does not
  parse is ignored rather than treated as a rejection, which is what pip does and what
  `index.mbt`'s resolver already does.
- `tools/fetch_upgrade_corpus.py` (388 lines), `fixtures/upgrade_corpus.mbt` and the
  `upgrade` record kind: 51 cases plus 3 undecidable inputs, replayed against `packaging`
  with the *same arguments* -- both the shortlist and the reason each candidate was dropped
  have to agree, so dropping a candidate for the wrong reason fails even when the shortlist
  matches. Two more mutations (43 total).
- `docs/upgrade-scenario.md`: the acceptance inputs, the rule order and the boundary of the
  answer.

### Changed

- The prerelease policy reaches the candidates **through the range**, so with no target
  range `Some(false)` has nothing to filter and prereleases are kept. That is the same
  choice `SpecifierSet::filter` makes for an empty specifier set; it is pinned by a unit
  test, by the corpus and by one of the new mutations.
- The corpus grew from 122 589 to **122 640** records (122 641 lines), 0 mismatches against
  `packaging` 26.3; the drift matrix is 24.2: 4492, 25.0: 2754, 26.0: 844, 26.3: 0.
- Root production MoonBit is 9778 lines and tests 7311 lines (293 blocks, all four
  backends). Four scenario reports are compared byte for byte across the four backends.

## Unreleased — M12: PEP 425 tag generation, and a tag-case defect the corpus had missed

### Added

- `tags.mbt` (448 lines): the *generation* side of PEP 425, which the library had been
  missing -- it could match and rank tags but not produce the ordered list. `cpython_tags`
  (explicit ABIs, then the stable ABI, then `none`, then the `abi3`/`abi3t` tail down to
  `cp32`), `generic_tags`, `pure_python_tags`, `compatible_tags`, `mac_platforms` (the
  10.x walk, the 11+ spelling, and the x86_64-only 10.x replay) and `tag_rank` (the
  selector rule, now shared with the resolver's candidate ordering). Every function takes
  the interpreter, the ABI list and the platform list as arguments: the host is still
  never read.
- `tools/fetch_tag_corpus.py` (518 lines) and `fixtures/tag_corpus.mbt`: 62 argument
  tuples plus 6 declared divergences, replayed against `packaging.tags` itself.
  `tools/diff_packaging.py` imports `reference_tag` and asks the reference the same
  question with the same arguments at replay time, so the fixture is an input list rather
  than a transcript. This is the only record kind that is not a document comparison.
- `tag` and `tag_divergence` record kinds, four mutations (41 total), and a
  `--check` for the tag fixture in the local gate and in CI.

### Fixed

- Wheel tag components are lowercased. `packaging`'s `Tag` lowercases the interpreter,
  the ABI and the platform in its constructor, so `CP312-CP312-Manylinux_2_17_X86_64`
  and the lowercase spelling are one tag; `parse_tag_set` kept the caller's case. The
  corpus had never noticed because every wheel filename in it -- curated and real -- spells
  its tags in lower case, so the two sides never disagreed about the spelling. Five
  curated filenames now spell them the other way, and `wheel-tag-case-not-normalized`
  (which puts the case back) is detected on 105 records where it used to be green.
- `tools/oracle_matrix.py` no longer reads a stale report. It removed nothing before
  running an oracle, so a sub-run that died early (an oracle without the API a record
  needs) left the previous run's JSON in place and the table below displayed it as this
  run's result. That happened while adding the tag corpus; the report file is now unlinked
  first.

### Changed

- Empty inputs that the reference answers from the running machine are refused rather
  than guessed, and the six cases are declared divergences: an empty Python version
  (`TAG_VERSION_REQUIRED`, twice), an empty interpreter name
  (`TAG_INTERPRETER_REQUIRED`), and an empty **platform** list (`TAG_PLATFORMS_REQUIRED`,
  three times). The last one is the subtle one: `platforms or platform_tags()` means an
  empty list is the same `[]` a caller would pass for a target that has none, and the
  reference answers it by probing the machine -- which also made the first version of the
  fixture depend on the machine that generated it.
- `create_compatible_tags_selector` (26.1) and `pure_python_tags` (26.3) are imported
  lazily, so the drift matrix can still replay the corpus with 24.2 / 25.0 / 26.0: those
  releases report `ReferenceUnavailable` for the `select` and `pure` cases instead of
  taking the whole harness down. The older-oracle rows now carry `tag-generation x24`.
- The corpus grew from 122 516 to **122 589** records, 0 mismatches against `packaging`
  26.3, and the drift matrix is 24.2: 4492, 25.0: 2754, 26.0: 844, 26.3: 0.
- Root production MoonBit is 9494 lines and tests 6976 lines (277 blocks, all four
  backends); `index.mbt`'s `tag_priority` delegates to `tag_rank` so the ranking rule
  lives in one place.

## Unreleased — M8 (continued): six PEP 751 divergences settled, real `uv` lock files

### Changed

- Six of the seven declared divergences from PEP 751 are gone. Re-reading the
  specification's own `Required?` lines settled all six towards the specification,
  because each of them was this library being *more permissive* than the spec — a
  defect rather than a design choice: `created-by` is required
  (`CREATED_BY_REQUIRED`, and `Pylock::created_by` returns `String` rather than
  `String?`), a file record must carry a non-empty `hashes` table
  (`FILE_HASHES_REQUIRED`), `upload-time` must be in UTC
  (`FILE_UPLOAD_TIME_NOT_UTC`; the spelling is still recorded verbatim, `Z` is not
  rewritten), `packages.version` may not sit next to a source tree
  (`PACKAGE_VERSION_NOT_ALLOWED` — `vcs` and `directory` are trees, `archive` and a
  local `path` are files), and `packages.version` is no longer *demanded* on an
  entry that names files (`PACKAGE_VERSION_REQUIRED` is gone; it is `Required? :
  no`, and only a SHOULD for an entry whose version is stable). The seventh stays:
  an unimplemented `lock-version` minor is rejected rather than warned about,
  because there is no warning channel here, which is the MUST side of the same
  paragraph. `pylock_cases/divergences.txt` went from seven entries to one.
- Every settled rule is pinned by an *ordinary* record, not merely removed from the
  divergence list: an accepted entry with wheels and no version, the two UTC
  spellings (`+00:00` and `-00:00`), one source-conflict case per pair of members,
  and a rejected case for each of the four rules, so a future regression fails as a
  plain mismatch instead of as a change of verdict on a declared divergence.
- The corpus grew from 122 507 to **122 516** records, 215 of them `pylock`, still
  0 mismatches against `packaging` 26.3, and the drift matrix is unchanged
  (24.2: 4474, 25.0: 2736, 26.0: 826, 26.3: 0).
- Root production MoonBit is 9042 lines and tests 6675 lines (259 blocks, all
  four backends) once the audit module below is included; this settlement added
  66 lines of library and 70 lines of tests on its own.
- `tools/mutation_probe.py` gained `--allow-dirty` for working on a deliberately
  modified tree, with an explicit warning that a leftover injection inflates the
  counts. The strict default is unchanged, and every mutation's own anchor is
  checked either way, so a table of source files this probe never edited is
  reported instead of silently accepted.

### Added

- `pylock_cases/uv/`: six `pylock.toml` files written by `uv 0.11.32`
  (`uv export --format pylock.toml`) for flask, requests, numpy, django, httpx and
  cattrs — 50 packages with real index URLs, real sha256 digests and sizes, and
  inline `wheels = [...]` arrays up to 77 KB. They are the only documents in the
  PEP 751 corpus that this repository did not write. `uv` writes and never reads,
  so they add independent *inputs*, not a second reading of the specification, and
  the verdict is still ours; what they do prove is that tightening the six rules
  did not cost real-world compatibility, because all six are accepted *after* the
  change. `pylock_cases/uv/provenance.txt` records where they came from and
  `regenerate.sh` how they were made; they are committed as inputs and never
  regenerated. `mbt_document` emits a long document as a concatenation of escaped
  chunks, because MoonBit's lexer refuses a single text segment past 65535
  characters and the numpy lock file is 77 KB.
- Five mutations in `tools/mutation_probe.py` (36 total now), one per settled rule,
  each restoring the leniency that was removed. The probe reported
  `pylock-ignores-source-exclusivity` as NOT DETECTED on its first run, and that
  was a gap in the *corpus* rather than in the library: the case meant to pin that
  rule also carried a `version` next to a source tree, so switching the check off
  still left the document rejected — by the version rule. A case only pins a rule
  when it is otherwise valid, which is now one conflict case per pair of members.

## 0.2.0 — cross-artifact package audit, 2026-09-15

### Added

- `audit_package`: a high-level join across PEP 508 requirements, core metadata,
  PEP 691 index responses, PEP 751 locks and an explicit target environment.
- Stable audit findings for identity, Python, environment, selected-version and
  sha256 inconsistencies, plus deterministic `PackageAudit::render` output.
- A runnable audit using real PyPI Flask metadata, five integration tests, and
  four-backend output parity in CI.
- `tools/source_metrics.py`, which reports production code separately from tests,
  examples, generated fixtures and Python verification tools.

### Changed

- Broaden the module description from a PEP 440 helper to the implemented Python
  packaging metadata toolkit; retain the no-network, no-install boundary.

## Unreleased — M8 (continued): PEP 751 differential corpus, per-value metadata records

> The aggregate numbers in this section are the state at that increment. The section
> above supersedes them: 122 516 records, 9042 production lines, 6675 test lines,
> 36 mutations, one declared PEP 751 divergence, 120 lock-file documents.

### Added

- `tools/fetch_pylock_corpus.py` (1523 lines): the differential corpus for PEP 751,
  written as a second reading of the specification. `packaging` has no
  `pylock.toml` reader, so this is deliberately *our* reading rather than an
  external oracle, and the module says so; what it does provide is a verdict per
  document plus a projection of every member, dependency and file record, written
  down once and imported by the harness so the two sides cannot drift apart.
- `pylock_cases/` (105 documents) and a `pylock` record kind: 24 curated accepted
  documents (the PEP's own example verbatim among them), 42 curated rejected ones
  one rule each, 32 single-edit mutations, 7 declared divergences, and 95 lock
  files derived from the real PEP 691 responses already in `index_corpus.mbt` —
  the file records' names, URLs, sha256s, sizes and upload times are those
  responses' own. 200 records, 0 mismatches.
- A `pylock_divergence` record kind, so the declared divergences travel with the
  corpus and are asserted in both directions rather than tolerated.
- A `meta_values` record kind (915 records): name, version, keywords,
  `provides-extra`, `requires-python`, the `Requires-Dist` count and summary
  presence, compared one value at a time against `packaging`. The existing `meta`
  record compares the verdict and the round trip, which cannot catch a wrong
  *value*: `packaging` strips and normalizes on the way in, so a spelling this
  library got wrong is normalized away by the very step meant to check it. A
  list-valued field also carries a count record, so a short list is a difference
  rather than a record that is simply absent.
- Six mutations in `tools/mutation_probe.py` (31 total now): four for the lock
  file — `lock-version` tolerance, source exclusivity, the fixed file-record
  order, the URL-derived filename — and two for the metadata rules below. The
  `Keywords` mutation is detected *only* through the new `meta_values` records.

### Fixed

- `Name` may not end in an underscore. `is_valid_name` ended with
  `is_ascii_alphanumeric(c) || c == "_"`, so `Name: demo_`, `d_` and `1_` were
  accepted where `packaging` reports `InvalidMetadata(field "name")`. An
  underscore is legal *inside* a name, which is what makes this easy to get wrong.
- `Provides-Extra` is validated by the same predicate and had the same hole.
- `Keywords` parts are stripped with Python's `str.strip()`, not with RFC 5322's
  WSP. Trimming with space and tab left the vertical tab and the form feed inside a
  part, so `Keywords: a,<VT>b` yielded `["a", "<VT>b"]` where `packaging` yields
  `["a", "b"]`. `strip_python_space` implements the set `str.strip()` uses.
- The differential protocol escapes every control character now. The emitter
  escaped backslash, tab, LF and CR only, so a raw vertical tab or form feed — a
  record separator to anything reading the corpus by lines, and a *line break* to
  the MoonBit lexer — split the record in half. Without this the new `Keywords`
  cases could not be expressed at all, which is how the hole was found. Both
  fixture generators escape the whole class as well when they write a document as
  a literal, instead of only the characters with a short spelling.

### Changed

- `examples/metadata-check` reads a real `pylock.toml` instead of a stand-in table
  of name/version pairs, parsing it with `Pylock::parse`, and reports how many
  locked entries apply to the target and how many were locked for another
  platform. Output is unchanged apart from the two new header lines, and still
  byte-identical on all four backends (md5 `2cedc437f5b3`).
- The corpus grew from 121 381 to **122 507** records, still 0 mismatches against
  `packaging` 26.3, and the drift matrix is unchanged (24.2: 4474, 25.0: 2736,
  26.0: 826, 26.3: 0).
- Library source is 8644 lines, tests 6389 lines (251 blocks, all four backends).

## Unreleased — M5: PEP 639 license expressions

### Added

- `licenses.mbt`: SPDX license expression canonicalization aligned with
  `packaging` 26.3 — 699 license identifiers and 79 exception identifiers,
  ASCII case folding, operator casing, the `+` suffix, `LicenseRef-` /
  `DocumentRef-` forms, the 200-level nesting limit, and PEP 685 normalization
  of `LicenseRef-` bodies. `canonicalize_license_file` validates a PEP 639
  license file path without normalizing it.
- A `license` record kind with 4000 mutated expressions: 120 951 records then
  agree with `packaging` 26.3, still 0 mismatches.
- `MarkerEnvironment::set` / `set_names` canonicalize the `extra` value and the
  members of a set-valued key, so a caller may hand over the spelling it read
  from `pyproject.toml`. `packaging` rewrites the environment it is given for
  the same reason (PEP 685 / PEP 735); without this the two disagreed whenever
  the group was not already spelled in canonical form.
- A fifth corpus environment, `oddnames`, whose extra and group members are
  deliberately not canonical: `extra = "Docs_Build"`,
  `extras = ["CLI", "docs_build"]`, `dependency_groups = ["DocsBuild"]`.

## Unreleased — M4: TOML 1.0 reader

### Added

- `toml.mbt`: a TOML 1.0 parser and canonical re-serializer, enough for
  `pyproject.toml` and `pylock.toml`. Ordered tables, all four string flavours,
  the four integer bases, floats with the special values, the five datetime
  shapes, arrays, inline tables, tables, arrays of tables and dotted keys.
- `fixtures/toml_corpus.mbt`: 83 conformance cases whose verdicts come from the
  reference reader `tomli`, generated by `tools/fetch_toml_corpus.py`.
- `toml_cases/leniencies.txt`: the four documents where the reference reader
  implements a relaxation that TOML 1.0 forbids (three TOML 1.1 additions, plus
  its arbitrary precision integers). The corpus asserts the divergence in both
  directions instead of tolerating it: a document that is declared lenient and
  is nevertheless accepted is reported as `lenient-drift`, which the harness
  treats as a mismatch.
- A `toml` record kind, which checks the verdict *and* that re-parsing the
  library's own re-serialization yields the same value tree.

### Fixed

- Multiline basic strings dropped their first character.
- Integers were `Int` (32-bit), so `0xDEADBEEF` was rejected on a wasm32 target;
  TOML integers are 64-bit and are now `Int64`.
- A number parse failure left the sign consumed, so `-inf` reported the wrong
  error at the wrong position.
- A newline inside an inline table reported the wrong code; it now has its own
  diagnostic, distinct from an unterminated table.
- `Toml::to_string` emitted a leading blank line.

## Unreleased — M8: PEP 751 lock files

### Added

- `pylock.mbt` (1214 lines): a reader and validator for `pylock.toml`, the file
  PEP 751 defines. Every member the specification names is read and checked --
  `lock-version` (which must be exactly `"1.0"`), `environments`, `requires-python`,
  `extras`, `dependency-groups`, `default-groups`, `created-by`, `[[packages]]` with
  `name`, `version`, `marker`, `requires-python`, `[[packages.dependencies]]`,
  `[packages.vcs]`, `[packages.directory]`, `[packages.archive]`,
  `[packages.sdist]`, `[[packages.wheels]]` and `packages.index`. The `[tool]`
  tables are ignored, as a reader is required to do.
  - Rejections are `VersionError::InvalidPylock(code, ordinal)` with stable
    codes built from the member they name (`<MEMBER>_REQUIRED`, `_TYPE`,
    `_NOT_TABLE`, `_NOT_ARRAY`, `_INVALID`, `_EMPTY`), so a caller can tell
    `[packages.vcs] type` from `packages.vcs` itself. `ordinal` is the structural
    index of the offending `[[packages]]` entry, or `0` for a document-level
    problem, matching `InvalidIndex`.
  - The source-exclusivity rule is enforced: a package entry may record one of
    `vcs`, `directory`, `archive`, a local `path` (the draft spelling) or a file
    list, and two of them is `PACKAGE_SOURCE_CONFLICT`.
  - `Pylock::is_applicable`, `Pylock::applicable_packages` and
    `Pylock::accepts_environment` answer "which entries apply here" for a
    caller-supplied `MarkerEnvironment`, and raise exactly where
    `Marker::evaluate` raises, so an environment that cannot answer a marker is
    reported rather than guessed at.
- `pylock_test.mbt` (1323 lines): 32 blocks, 251 blocks per backend now. The
  example PEP 751 prints is parsed byte for byte, including its `[tool]` table and
  `[[packages.attestation-identities]]` entries, which this reader ignores.
- Seven documented divergences from the specification, each pinned by a block and
  registered in `pylock_cases/divergences.txt`: `created-by` may be absent and an
  empty value counts as absent; a redundant `version` next to a source tree is
  accepted (the specification's MUST NOT is a locker-side rule); a file record may
  omit `hashes` (the digest is then simply unknown); `upload-time` is recorded
  verbatim rather than normalized to UTC; a `lock-version` other than `1.0` is
  rejected outright, where the specification would have the reader warn; and
  `packages.version` is required on an entry that names files, where the
  specification makes it a SHOULD. The last one was found while writing the
  corpus -- the generator read the specification's `Required?` line as "optional"
  and the harness reported the difference, which is the corpus doing its job.

### Measured, not assumed

Three expectations in the first draft of `pylock_test.mbt` were wrong and the
mistakes were caught by running the suite, not by reading it: `sys_platform ===
'linux'` and `'docs' in extras` are *valid* PEP 508 markers and `>=3.9,` is a
valid PEP 440 specifier set, all three confirmed against `packaging` 26.3
(`Marker`, `SpecifierSet`) before the assertions were corrected. Two further
blocks were checking the test helper rather than the library: a fragment written
as a raw block has no trailing newline, so concatenating two of them produced one
malformed line, and `created-by` was being written twice, so a type error showed
up as a duplicate key.

## Unreleased — M7: offline index and candidate resolution

### Added

- `index.mbt` (1256 lines): a strict RFC 8259 JSON reader, the PEP 691
  simple-repository mapping, an offline directory scan and the candidate
  resolver.
  - The JSON reader rejects duplicate member names (`JSON_DUPLICATE_KEY`) where
    RFC 8259 only says names *SHOULD* be unique: a shadowed `url` or `hashes`
    member is exactly the kind of thing a PEP 691 consumer must never miss.
    Numbers keep their source text, so nothing depends on floating point.
  - `SimpleIndex::parse` maps a response, `SimpleIndex::wheels` / `sdists` split
    it, and an entry that is neither a wheel nor an sdist is a defect
    (`INDEX_UNKNOWN_DIST`) rather than something to drop.
  - `LocalIndex::scan` takes an injected `DirectoryLister`, because
    `moonbitlang/core` has no filesystem package; a name that is not a
    distribution is ignored, which is the opposite of the index rule on purpose.
  - `resolve_candidates`, `select_best` and `explain_rejection` implement pip's
    selection: name, specifier, prerelease policy over all name-matching versions
    at once, `Requires-Python`, and PEP 425 tag intersection, ordered by version,
    wheel-before-sdist, tag priority, PEP 427 build number and finally the file
    name -- the last step being an addition, because pip leaves a tie to server
    order and a resolver that writes lock files must be deterministic.
- `VersionError::InvalidIndex(String, Int)`, plus its `diagnostic` arm.
- `index_test.mbt`: 52 blocks covering the JSON reader, the mapping, the scan and
  the resolver, asserting error codes. The suite is 219 blocks per backend.
- `tools/fetch_index_corpus.py` and `index_cases/`: 21 curated documents (nine the
  specification accepts, twelve it rejects) and 97 real PEP 691 responses from a
  public index, fetched through the JSON API. Responses larger than 20 files or
  40 versions are reduced to those heads, which the fixture states.
- `index_cases/divergences.txt`: the one document where this library deliberately
  answers differently from Python's `json` (a duplicate member name), with the
  reason. The generator checks the reference's half, the harness both.
- Three record kinds: `index` (verdict plus the PEP 691 projection, re-derived
  independently in Python from the specification), `index_dir` (the scan's
  classification of an injected listing) and `resolve` (the selected files in
  order and the reason each other file was rejected, recomputed in Python with
  `packaging`). Plus the `index_divergence` input record. Corpus grows from
  121 239 to 121 381 records, still 0 mismatches.
- `examples/resolve` (570 lines): scenario 2 end to end. It takes one PEP 691
  response, converts every `files[]` entry with `SimpleIndexFile::to_index_file`,
  applies a PEP 592 yank policy **in the example** (the library has no yank
  policy on purpose -- `IndexFile` carries no yank field, because only the caller
  that read `SimpleIndexFile::yanked` knows whether a yanked release is
  acceptable), resolves three requirements with `resolve_candidates`, prints the
  first rule that dropped every other file with `explain_rejection`, and finishes
  with the same requirement against a wheelhouse through `LocalIndex::scan` with
  an injected `DirectoryLister`. All five rejection reasons appear at least once,
  the yank policy visibly changes the answer (1.2.1 with it, the yanked 1.4.0
  without it), and `INDEX_UNKNOWN_DIST` / `INDEX_NO_FS` are both really raised.
  Inputs are compiled in, for the same reason as scenario 1: core has no
  filesystem package and no HTTP client. Output is byte identical on the four
  backends (md5 `e58c1ff44ab6`); CI runs it on all four and compares.

## Unreleased — M6: core metadata

### Added

- `metadata.mbt`: a `METADATA` / `PKG-INFO` reader and validator for the core
  metadata specification (PEP 566 as amended by 621, 639, 643, 685 and 753):
  the RFC 822 header/body split with unfolding, the version gate, the multi-use
  and single-use field rules, `Requires-Dist` through `Requirement::parse`,
  `Requires-Python` as a `SpecifierSet`, PEP 639 license expressions and license
  files, mailbox parsing, `Project-URL` labels and the deprecated 1.x fields.
  Every rejection is a stable `VersionError::InvalidMetadata(code, offset)`.
- `Metadata::requirements` / `requires_python` / `extras` / `is_compatible` /
  `diagnostics` / `to_string`: the canonical re-rendering re-parses to the same
  metadata, which is what the round trip check below relies on.
- `VersionError::InvalidMetadata(String, Int)`, plus its `diagnostic` arm.
- `metadata_test.mbt`: 47 blocks pinned against `packaging` 26.3, one per rule,
  asserting the error code as well as the rejection, plus a corpus block that
  replays 40 measured documents. The suite is 167 blocks on each of the four
  backends.
- `tools/fetch_metadata_corpus.py` and `metadata_cases/`: 42 curated rule cases
  and 239 real `METADATA` documents fetched from the PEP 658 `.metadata` sidecars
  of real PyPI wheels (593 downloaded, the rest dropped for size, counted in
  `fixtures/metadata_corpus.json`).
- `metadata_cases/divergences.txt`: the seven documents where this library
  deliberately answers differently from `packaging` 26.3, each with the
  direction and the reason. The generator checks the reference's half and the
  differential harness checks both halves on every replay.
- A `meta` record kind (accept verdict, error code, canonical re-rendering) and a
  `meta_divergence` input record, compared against
  `packaging.metadata.Metadata.from_email(data, validate=True)`. Corpus grows
  from 120 951 to 121 239 records, still 0 mismatches.
- `examples/metadata-check`: scenario 1 end to end. It parses real `METADATA`
  documents, decides each `Requires-Dist` against a lock table and a fixed
  environment, and prints `ok` / `OUT OF RANGE` / `not applicable` /
  `not locked` / `UNPARSABLE` per line plus a summary. Inputs are compiled in
  rather than read from disk, because `moonbitlang/core` has no filesystem
  package and the library stays dependency free; the documents are the same real
  PyPI `METADATA` files the corpus uses. Its output is byte identical on the four
  backends and CI runs it on all of them.

### Changed

- `Author-email` / `Maintainer-email` are parsed into `(name, address)` pairs but
  no longer fail a document: a present-but-empty value counts as absent, and a
  list that does not parse is reported by `diagnostics` as
  `author-email-unparsable`. Measured, not assumed: five real documents that PyPI
  serves (`kubernetes-10.0.0`, `kubernetes-10.0.1`, `kubernetes-10.1.0` with
  `Author-email: ` and `torch-1.0.0` with `Author-email: UNKNOWN`) are rejected by
  the stricter rule and accepted by the reference implementation. `packaging`
  does not validate the field at all.
- `tools/mutation_probe.py` grew from 16 to 20 injected defects: the metadata
  version gate, `Requires-Dist` validation and both halves of the PEP 639
  `License-Expression` exclusivity rule. Two behaviours are deliberately *not*
  covered there (empty `Author-email`, unparsable address list) because the
  reference implementation does not look at the field, so the corpus cannot see
  the difference; the unit tests cover them instead.

## Unreleased — tooling

### Fixed

- `tools/diff_packaging.py` picked up whichever TOML reader the host had, so CI
  (Python 3.13, stdlib `tomllib`, strict TOML 1.0) judged the fixture's four
  documented leniencies against a reader that does not implement them and
  reported three false mismatches. The harness now prefers `tomli` — the reader
  the fixture was generated with — falls back to `tomllib`, states which one it
  used in the report and on stdout, and treats "both reject" as agreement
  regardless of the reader. CI pins `tomli==2.4.1` and asserts the version.
- `tools/oracle_matrix.py` read each per-oracle report without checking that it
  exists, so a sub-run that died turned into a bare `FileNotFoundError` that hid
  the real message, and the drift table silently lost those rows. It now reports
  the sub-run's stderr and exit status instead.
- `tools/diff_packaging.py` no longer dies when the reference implementation
  itself raises: packaging 25.0 and older hand an invalid escape sequence to
  `ast.parse` and raise `SyntaxError` where 26.3 raises `InvalidMarker`. Those
  records (27-28 of them) are now reported as a difference with the cause
  `oracle-crash`, so every oracle replays all 120 951 records and older releases
  produce a complete drift table.
- The build toolchain and CI disagreed about formatting: `moon` 0.1.20260713
  accepted `{ lhs, op, rhs }` where `moon` 0.1.20260904 (the release CI installs)
  requires `{ lhs, op, rhs, }`, so `moon fmt --check` failed there. The sources
  are formatted with the newer release and every claim in the docs is re-checked
  against it; the trailing-comma rule is the only difference.

### Added

- `tools/mutation_probe.py` grew from 7 to 16 injected defects, covering M2–M5:
  marker normalization (both the environment half and the set members), the
  `in` operand order, the marker vocabulary, requirement marker validation, SPDX
  case folding, and three TOML defects (wrapped inline tables, a multiline
  string losing its first character, integers narrowed to 32 bits). Every
  mutation must be reported by the corpus; one that stays green is a gap in the
  experiment, not a pass.
- `tools/mutation_probe.py --list`, and a default oracle of
  `~/oracle-versions/venv26.3/bin/python` so the probe needs no TOML fallback.

## Unreleased — M3: PEP 508 environment markers

### Added

- `markers.mbt`: the closed marker vocabulary, the `and`/`or` grammar with its
  whitespace rules, Python string-literal decoding, PEP 685 normalization of
  `extra`/`extras`/`dependency_groups` values, canonical rendering with the
  minimum parentheses, and evaluation against a caller-supplied
  `MarkerEnvironment`. `MarkerError` reports an undefined key, an undefined
  comparison and a set-valued key used outside a membership test separately.
- `marker`, `marker_env` and `marker_eval` record kinds: acceptance, canonical
  rendering, and evaluation of every curated expression against four complete
  environments plus 4000 mutations.

### Changed

- `Requirement::parse` now hands its marker to `markers.mbt`, so `ex0tra == "x"`
  is rejected where the oracle rejects it. `VersionError` gains
  `InvalidMarker`.

## Unreleased — M2: PEP 508 requirement lines

### Added

- `requirements.mbt`: `Requirement::parse` for both operand forms
  (`name[extras] specifier ; marker` and `name[extras] @ url ; marker`),
  extras deduplication and sorting, constraint normalization, and the
  parenthesised specifier spelling the oracle still accepts.
- A `req` record kind: `Requirement` fields compared against
  `packaging.requirements.Requirement`.
- `requirements_test.mbt`.

### Fixed

- The URL form required whitespace before its marker, and a `;` could be part of
  a URL; both are now handled the way the tokenizer does.
- The extras list rejected `foo[  ]`, and accepted a comma with no name after
  it, which the oracle rejects.

## Unreleased — M1: packaging metadata helpers

### Added

- `utils.mbt` (M1, 331 lines): PEP 503 `canonicalize_name`, PEP 625
  `canonicalize_version` in both the index-key and display forms, PEP 427
  `parse_wheel_filename` (build tags and compressed tag set expansion) and
  `parse_sdist_filename`, with `WheelFilename` / `SdistFilename` result types.
- `VersionError` gains `InvalidName` and `InvalidFilename`, so filename and name
  failures carry stable codes like the existing version and specifier errors.
- `fixtures/` grows to four real-world arrays: 3000 versions, 500 constraints,
  600 verbatim `Requires-Dist` entries and 900 distribution filenames.
- Two new differential record kinds, `canon` and `file`, adding 11 104 records.
- `tools/mutation_probe.py`, which injects seven deliberate defects and asserts
  the corpus reports them; all seven are detected.

### Fixed

- Wheel tag sets were ordered with MoonBit's default `String` comparison, which
  orders by length first; PEP 425 ordering is by code point. Caught by
  `utils_test.mbt`, the same class of mistake as the earlier local-segment bug.

### Changed

- Corpus grows from 87 916 to 99 020 records, all agreeing with `packaging` 26.3.
- The oracle matrix now also reports `filename-grammar` drift: packaging 26.3
  tightened wheel and sdist validation (empty project names, empty tag
  components and non-identifier interpreters are rejected from 26.3 onwards).

## Unreleased — broader differential experiment

### Added

- `fixtures/` package with a real-world PyPI corpus: 3000 version strings and 500
  constraint strings from 97 packages, generated by `tools/fetch_pypi_corpus.py`
  (deterministic, provenance in `fixtures/pypi_corpus.json`).
- `examples/diff`, a deterministic corpus emitter with four sources (curated,
  grammar-generated, single-character mutations, real PyPI metadata) covering six
  record kinds and three prerelease modes; 87 916 records, byte identical on
  wasm, wasm-gc, js and native.
- `tools/diff_packaging.py`, the differential harness: replays every record against
  CPython `packaging`, groups mismatches by source, kind, mode and cause, and writes
  a JSON report.
- `tools/target_parity.py`, which fails if any backend emits a different corpus.
- `tools/oracle_matrix.py`, which replays one captured corpus against several
  `packaging` releases and prints the drift matrix.
- `examples/bench`, a throughput harness over the same corpus.
- `docs/experiment.md` and `docs/experiment-results.md`.

### Fixed

Found by the differential corpus, all three pinned by regression tests:

- Accept the full PEP 440 suffix grammar: `1.0post1`, `1.0-post1`, `1.0_post1`,
  `1.0a1post2dev3`, `1.0a1-5` and similar spellings were rejected.
- Compare textual local-version segments lexically instead of by length, so
  `0.0+a1 < 0+x` as PEP 440 requires.
- Reject whitespace inside a specifier's version operand (`!=2.0 .*`,
  `>=1.0 <=2.0`) and apply packaging's operand restrictions to `===`
  (no whitespace, `;` or `)`).

### Changed

- CI now runs a dedicated `differential` job: four-backend corpus parity,
  comparison against `packaging==26.3`, a byte-identity check across runs, and a
  drift matrix against `packaging==25.0`.
- `examples/oracle` and `tools/check_packaging.py` are replaced by the tools above;
  the old script compared 2050 records, the new harness compares 87 916 and reports
  drift causes.
- Documentation now states what the experiment does and does not show.

## 2026-09-10 review fixes

- Correct nested pre/post/dev ordering, zero-padded wildcard matching and local-label constraints.
- Correct exclusive-boundary post/dev exclusions and case-insensitive parsed-version `===`.
- Add explicit prerelease policy and stable-first candidate filtering (packaging 26.3 behavior).
- Add regression tests and 2050 independent packaging comparisons in JS CI.
- Correct documentation and replace application prose with a human-author preparation checklist.
- These changes are source updates, not a claim of MoonCakes publication.

All notable changes to this project are documented in this file.

## [0.1.0] - 2026-09-10

### Added

- PEP 440 version parser and normalizer (`Version::parse`, `Version::normalize`, `Version::to_string`).
- PEP 440 ordering with `Eq`, `Compare`, and `Show` implementations.
- Version specifier parser and filter (`SpecifierSet::parse`, `contains`, `filter`).
- Operators `==`, `!=`, `<`, `<=`, `>`, `>=`, `~=`, `===`, and `.*` wildcards.
- Stable `VersionError` diagnostics.
- Test suite covering normalization examples, rejection cases, comparison edge cases, specifier operators, pre-release rules, wildcards, and comparison properties.
- Runnable `examples/basic`.
- Documentation: `README.md`, `README.mbt.md`, `docs/design.md`, `docs/provenance.md`, `docs/applicant-notes.md`, `docs/proposal-draft.md`.
- GitHub Actions CI for wasm, wasm-gc, js, and native targets.
