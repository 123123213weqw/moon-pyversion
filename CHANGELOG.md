# Changelog

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