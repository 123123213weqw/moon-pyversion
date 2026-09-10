# Changelog

## Unreleased — 2026-09-10 review fixes

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
