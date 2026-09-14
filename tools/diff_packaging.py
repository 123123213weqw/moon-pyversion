#!/usr/bin/env python3
"""Independent differential oracle for Moon PyVersion.

The MoonBit package under test never links against CPython.  This harness runs
``examples/diff`` (a deterministic corpus emitter), replays every emitted
record against PyPA ``packaging`` and reports mismatches grouped by corpus
source, record kind and prerelease mode.

The corpus has four sources, tagged in the emitter output:

* ``curated``  - a hand written list of PEP 440 corners (exhaustive pairs)
* ``generated``- versions and specifiers sampled from the PEP 440 grammar
* ``mutated``  - one-character mutations plus outright junk (mostly illegal)
* ``pypi``     - real version strings and real constraint strings taken from
                 the PyPI JSON API by ``tools/fetch_pypi_corpus.py``

Usage::

    python -B tools/diff_packaging.py                    # oracle = installed packaging
    python -B tools/diff_packaging.py --oracle-version 26.3 --json report-26.3.json
    python -B tools/diff_packaging.py --capture /tmp/corpus.tsv
    python -B tools/diff_packaging.py --input /tmp/corpus.tsv --tolerate-drift
    python -B tools/diff_packaging.py --target native

``--capture`` plus ``--input`` lets one emitter run be replayed against several
``packaging`` releases without rebuilding the corpus (see
``tools/oracle_matrix.py``). Differences are bucketed by cause
(``version-grammar``, ``specifier-grammar``, ``ordering``, ``prerelease-policy``,
``compatible-release-range``) so a drifted oracle stays readable.

Exit status: 0 = agreement, 1 = mismatches, 2 = environment or protocol error.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import time
from collections import Counter, defaultdict
from pathlib import Path

from packaging import __version__ as ORACLE_VERSION
from packaging.licenses import (
    InvalidLicenseExpression,
    canonicalize_license_expression as reference_canonicalize_license,
)
from packaging.markers import InvalidMarker, Marker
from packaging.markers import UndefinedComparison as MarkerUndefinedComparison
from packaging.markers import UndefinedEnvironmentName as MarkerUndefinedEnvironmentName

# The TOML verdicts in `fixtures/toml_corpus.mbt` come from `tomli` 2.4.1, so
# `tomli` is preferred here: it is the reader the corpus was generated with, and
# it implements three relaxations that `tomllib` (strict TOML 1.0) rejects. Both
# readers are used only to judge the library's verdict, never to define it, and
# the harness states which one it used.
try:
    import tomli as toml_reader
except ImportError:  # pragma: no cover - tomli is a hard requirement of CI
    try:
        import tomllib as toml_reader
    except ImportError:
        # Only the `toml` records need a reader, so a missing one is reported
        # when one of those records is actually checked, not at import time.
        toml_reader = None

from packaging.requirements import InvalidRequirement, Requirement
from packaging.specifiers import InvalidSpecifier, SpecifierSet
from packaging.utils import (
    InvalidSdistFilename,
    InvalidWheelFilename,
    canonicalize_name,
    canonicalize_version,
    parse_sdist_filename,
    parse_wheel_filename,
)
from packaging.version import InvalidVersion, Version

MODES = {"auto": None, "any": True, "none": False}

# field count per record kind, including the leading source field
ARITY = {
    "parse": 5,
    "spec": 4,
    "cmp": 5,
    "contains": 6,
    "filter": 6,
    "order": 4,
    "canon": 6,
    "file": 9,
    "req": 9,
    "marker": 5,
    "marker_env": 4,
    "marker_eval": 6,
    "toml": 6,
    "license": 5,
}

EXIT_OK = 0
EXIT_MISMATCH = 1
EXIT_ERROR = 2


class ProtocolError(Exception):
    """The emitter produced a record this harness cannot interpret."""


class Oracle:
    """Memoized view of the packaging reference implementation."""

    def __init__(self) -> None:
        self._versions: dict[str, Version | None] = {}
        self._specs: dict[str, SpecifierSet | None] = {}
        self._requirements: dict[str, Requirement | None] = {}
        self._markers: dict[str, Marker | None] = {}
        self.marker_envs: dict[str, dict[str, str | frozenset[str]]] = {}

    def version(self, raw: str) -> Version | None:
        if raw not in self._versions:
            try:
                self._versions[raw] = Version(raw)
            except InvalidVersion:
                self._versions[raw] = None
        return self._versions[raw]

    def specifier_set(self, raw: str) -> SpecifierSet | None:
        if raw not in self._specs:
            try:
                self._specs[raw] = SpecifierSet(raw)
            except InvalidSpecifier:
                self._specs[raw] = None
        return self._specs[raw]

    def requirement(self, raw: str) -> Requirement | None:
        if raw not in self._requirements:
            try:
                self._requirements[raw] = Requirement(raw)
            except InvalidRequirement:
                self._requirements[raw] = None
        return self._requirements[raw]

    def marker(self, raw: str) -> Marker | None:
        if raw not in self._markers:
            try:
                self._markers[raw] = Marker(raw)
            except (InvalidMarker, ValueError):
                self._markers[raw] = None
        return self._markers[raw]

    def accepted_versions(self) -> int:
        return sum(1 for value in self._versions.values() if value is not None)

    def accepted_specifier_sets(self) -> int:
        return sum(1 for value in self._specs.values() if value is not None)


def check_record(oracle: Oracle, parts: list[str]) -> str | None:
    """Return a human readable mismatch, or None when both sides agree."""
    kind = parts[1]
    if kind == "parse":
        raw, status, detail = parts[2], parts[3], parts[4]
        parsed = oracle.version(raw)
        if status == "ok":
            if parsed is None:
                return f"{raw!r}: moonbit accepts, packaging rejects"
            if str(parsed) != detail:
                return (
                    f"{raw!r}: moonbit normalizes to {detail!r}, "
                    f"packaging to {str(parsed)!r}"
                )
        elif status == "bad":
            if parsed is not None:
                return f"{raw!r}: moonbit rejects, packaging accepts as {str(parsed)!r}"
        else:
            return f"unknown parse status {status!r}"
        return None

    if kind == "spec":
        raw, status = parts[2], parts[3]
        parsed = oracle.specifier_set(raw)
        expected = "ok" if parsed is not None else "bad"
        if expected != status:
            return f"{raw!r}: moonbit says {status!r}, packaging says {expected!r}"
        return None

    if kind == "cmp":
        left, right, sign = parts[2], parts[3], parts[4]
        a, b = oracle.version(left), oracle.version(right)
        if a is None or b is None:
            bad = left if a is None else right
            return f"emitted an ordering for unparseable input {bad!r}"
        expected = (a > b) - (a < b)
        try:
            actual = int(sign)
        except ValueError:
            return f"ordering sign {sign!r} is not an integer"
        if actual != expected:
            return f"moonbit ordered {left!r} vs {right!r} as {actual}, packaging as {expected}"
        return None

    if kind == "contains":
        mode, spec_raw, version_raw, actual = parts[2], parts[3], parts[4], parts[5]
        spec = oracle.specifier_set(spec_raw)
        version = oracle.version(version_raw)
        if spec is None:
            return f"emitted a membership test for unparseable specifier {spec_raw!r}"
        if version is None:
            return f"emitted a membership test for unparseable version {version_raw!r}"
        expected = spec.contains(version, prereleases=MODES[mode])
        if str(expected).lower() != actual:
            return (
                f"{spec_raw!r} contains {version_raw!r} (mode={mode}): "
                f"moonbit says {actual}, packaging says {str(expected).lower()}"
            )
        return None

    if kind == "filter":
        mode, spec_raw, candidates_raw, accepted_raw = (
            parts[2],
            parts[3],
            parts[4],
            parts[5],
        )
        spec = oracle.specifier_set(spec_raw)
        if spec is None:
            return f"emitted a filter for unparseable specifier {spec_raw!r}"
        candidates = [oracle.version(item) for item in candidates_raw.split("|")]
        if any(item is None for item in candidates):
            names = candidates_raw.split("|")
            bad = [name for name in names if oracle.version(name) is None]
            return f"emitted a filter over unparseable candidates {bad[:3]!r}"
        expected = [
            str(item)
            for item in spec.filter(candidates, prereleases=MODES[mode])
        ]
        actual = accepted_raw.split("|") if accepted_raw else []
        if actual != expected:
            return (
                f"{spec_raw!r} filter (mode={mode}): moonbit kept {actual!r}, "
                f"packaging kept {expected!r}"
            )
        return None

    if kind == "canon":
        subkind, raw, primary, secondary = parts[2], parts[3], parts[4], parts[5]
        if subkind == "name":
            expected = canonicalize_name(raw)
            if expected != primary:
                return f"canonicalize_name({raw!r}): moonbit {primary!r}, packaging {expected!r}"
            return None
        if subkind == "version":
            expected_key = canonicalize_version(raw)
            expected_display = canonicalize_version(raw, strip_trailing_zero=False)
            if expected_key != primary or expected_display != secondary:
                return (
                    f"canonicalize_version({raw!r}): moonbit key {primary!r} / display "
                    f"{secondary!r}, packaging key {expected_key!r} / display "
                    f"{expected_display!r}"
                )
            return None
        return f"unknown canon sub kind {subkind!r}"

    if kind == "file":
        subkind, raw, status = parts[2], parts[3], parts[4]
        expected_name, expected_version = parts[5], parts[6]
        expected_build, expected_tags = parts[7], parts[8]
        if subkind == "wheel":
            try:
                name, version, build, tags = parse_wheel_filename(raw)
            except (InvalidWheelFilename, InvalidVersion):
                if status != "bad":
                    return f"parse_wheel_filename({raw!r}): moonbit accepts, packaging rejects"
                return None
            if status != "ok":
                return f"parse_wheel_filename({raw!r}): moonbit rejects, packaging accepts"
            build_text = "-" if build == () else f"{build[0]}:{build[1]}"
            tags_text = "|".join(sorted(str(tag) for tag in tags))
            if (name, str(version), build_text, tags_text) != (
                expected_name,
                expected_version,
                expected_build,
                expected_tags,
            ):
                return (
                    f"parse_wheel_filename({raw!r}): moonbit "
                    f"{(expected_name, expected_version, expected_build, expected_tags)!r}, "
                    f"packaging {(name, str(version), build_text, tags_text)!r}"
                )
            return None
        if subkind == "sdist":
            try:
                name, version = parse_sdist_filename(raw)
            except (InvalidSdistFilename, InvalidVersion):
                if status != "bad":
                    return f"parse_sdist_filename({raw!r}): moonbit accepts, packaging rejects"
                return None
            if status != "ok":
                return f"parse_sdist_filename({raw!r}): moonbit rejects, packaging accepts"
            if (name, str(version)) != (expected_name, expected_version):
                return (
                    f"parse_sdist_filename({raw!r}): moonbit "
                    f"{(expected_name, expected_version)!r}, packaging {(name, str(version))!r}"
                )
            return None
        if subkind == "other":
            # Neither parser may accept a name with a different extension.
            accepted = _any_filename_parser_accepts(raw)
            expected = "ok" if accepted else "bad"
            if expected != status:
                return (
                    f"filename {raw!r}: moonbit says {status!r}, packaging says {expected!r} "
                    f"(no matching extension)"
                )
            return None
        return f"unknown file sub kind {subkind!r}"

    if kind == "req":
        raw, status, name, extras_raw, constraint, url, marker = parts[2:]
        expected = oracle.requirement(raw)
        if expected is None:
            if status != "bad":
                return f"Requirement({raw!r}): moonbit accepts, packaging rejects"
            return None
        if status != "ok":
            return f"Requirement({raw!r}): moonbit rejects, packaging accepts"
        actual_extras = [] if extras_raw == "-" else extras_raw.split("|")
        expected_extras = sorted(expected.extras)
        if name != expected.name:
            return f"Requirement({raw!r}).name: moonbit {name!r}, packaging {expected.name!r}"
        if actual_extras != expected_extras:
            return (
                f"Requirement({raw!r}).extras: moonbit {actual_extras!r}, "
                f"packaging {expected_extras!r}"
            )
        expected_constraint = str(expected.specifier)
        if constraint != expected_constraint:
            return (
                f"Requirement({raw!r}).specifier: moonbit {constraint!r}, "
                f"packaging {expected_constraint!r}"
            )
        expected_url = expected.url if expected.url is not None else "-"
        if url != expected_url:
            return f"Requirement({raw!r}).url: moonbit {url!r}, packaging {expected_url!r}"
        # Only marker presence is compared here; rendering markers canonically
        # belongs to the marker module.
        actual_has_marker = marker != "-"
        expected_has_marker = expected.marker is not None
        if actual_has_marker != expected_has_marker:
            return (
                f"Requirement({raw!r}).marker presence: moonbit {actual_has_marker}, "
                f"packaging {expected_has_marker}"
            )
        return None

    if kind == "marker_env":
        name, assignments = parts[2], parts[3]
        if name in oracle.marker_envs:
            return f"marker_env {name!r} declared twice"
        env: dict[str, str | frozenset[str]] = {}
        for entry in assignments.split(";"):
            if not entry:
                continue
            key, _, value = entry.partition("=")
            if not key:
                return f"marker_env {name!r} has an entry without a key: {entry!r}"
            if key.startswith("set:"):
                env[key[4:]] = frozenset(part for part in value.split(",") if part)
            else:
                env[key] = value
        oracle.marker_envs[name] = env
        return None

    if kind == "marker":
        raw, status, rendered = parts[2], parts[3], parts[4]
        expected = oracle.marker(raw)
        if expected is None:
            if status != "bad":
                return f"Marker({raw!r}): moonbit accepts, packaging rejects"
            return None
        if status != "ok":
            return f"Marker({raw!r}): moonbit rejects, packaging accepts"
        try:
            canonical = str(expected)
        except ValueError as error:
            return f"Marker({raw!r}): packaging cannot render it either ({error})"
        if rendered != canonical:
            return f"Marker({raw!r}): moonbit {rendered!r}, packaging {canonical!r}"
        return None

    if kind == "marker_eval":
        env_name, raw, status, detail = parts[2], parts[3], parts[4], parts[5]
        if env_name not in oracle.marker_envs:
            return f"marker_eval uses undeclared environment {env_name!r}"
        environment = oracle.marker_envs[env_name]
        marker = oracle.marker(raw)
        if marker is None:
            if status != "bad":
                return f"Marker({raw!r}): moonbit accepts, packaging rejects"
            return None
        if status == "bad":
            return f"Marker({raw!r}): moonbit rejects, packaging accepts"
        try:
            expected = marker.evaluate(environment, context="metadata")
        except MarkerUndefinedEnvironmentName:
            expected_kind, expected = "UndefinedEnvironmentName", None
        except MarkerUndefinedComparison:
            expected_kind, expected = "UndefinedComparison", None
        except Exception as error:  # noqa: BLE001
            expected_kind, expected = f"other:{type(error).__name__}", None
        else:
            expected_kind = None
        if expected_kind is None:
            if status != "ok":
                return (
                    f"Marker({raw!r}).evaluate({env_name}): moonbit raised {detail!r}, "
                    f"packaging returned {expected}"
                )
            expected_text = "true" if expected else "false"
            if detail != expected_text:
                return (
                    f"Marker({raw!r}).evaluate({env_name}): moonbit {detail!r}, "
                    f"packaging {expected}"
                )
            return None
        if status != "err":
            return (
                f"Marker({raw!r}).evaluate({env_name}): moonbit {status}/{detail!r}, "
                f"packaging raised {expected_kind}"
            )
        if EQUIVALENT_ERROR_KINDS.get(detail, detail) != expected_kind:
            return (
                f"Marker({raw!r}).evaluate({env_name}): moonbit raised {detail!r}, "
                f"packaging raised {expected_kind!r}"
            )
        return None

    if kind == "toml":
        if toml_reader is None:
            raise ProtocolError(
                "toml records need a reference reader: run with Python 3.11+ or "
                "install tomli in the oracle interpreter"
            )
        name, document, status, rendered = parts[2], parts[3], parts[4], parts[5]
        if status == "lenient-drift":
            # The emitter only writes this when a document that is declared to be
            # a TOML 1.0 leniency parses anyway, i.e. when the library silently
            # grew as loose as the reference reader.
            return (
                f"TOML case {name!r}: declared a TOML 1.0 leniency (the library "
                "rejects, the reference reader accepts), but the library accepts "
                "it now"
            )
        try:
            expected_value = toml_reader.loads(document)
        except toml_reader.TOMLDecodeError:
            if status == "ok":
                return f"TOML case {name!r}: moonbit accepts, the reference reader rejects"
            # Both reject the document, so they agree. That includes a declared
            # leniency under a reader stricter than the pinned one (the strict
            # TOML 1.0 reader in the standard library rejects all of them); that
            # the declared leniencies are leniencies at all is checked where the
            # fixture is generated, against the pinned reader.
            return None
        if status == "lenient":
            # The divergence is the point of the record, and the emitter only
            # writes `lenient` after a rejection, so both halves hold here: the
            # reference accepts and the library does not.
            return None
        if status != "ok":
            return f"TOML case {name!r}: moonbit rejects, the reference reader accepts"
        if rendered == "-":
            return f"TOML case {name!r}: accepted but not re-serialized"
        try:
            round_tripped = toml_reader.loads(rendered)
        except toml_reader.TOMLDecodeError as error:
            return f"TOML case {name!r}: the re-serialization does not re-parse ({error})"
        expected_form = _toml_shape(expected_value)
        actual_form = _toml_shape(round_tripped)
        if expected_form != actual_form:
            return (
                f"TOML case {name!r}: re-serialization changed the document\n"
                f"      expected {expected_form}\n      got      {actual_form}"
            )
        return None

    if kind == "license":
        raw, status, canonical = parts[2], parts[3], parts[4]
        try:
            expected = reference_canonicalize_license(raw)
        except InvalidLicenseExpression:
            if status != "bad":
                return (
                    f"canonicalize_license_expression({raw!r}): moonbit accepts, "
                    "packaging rejects"
                )
            return None
        if status != "ok":
            return (
                f"canonicalize_license_expression({raw!r}): moonbit rejects, "
                f"packaging returns {expected!r}"
            )
        if canonical != expected:
            return (
                f"canonicalize_license_expression({raw!r}): moonbit {canonical!r}, "
                f"packaging {expected!r}"
            )
        return None

    if kind == "order":
        inputs_raw, sorted_raw = parts[2], parts[3]
        inputs = [oracle.version(item) for item in inputs_raw.split("|")]
        ordered = [oracle.version(item) for item in sorted_raw.split("|")]
        if any(item is None for item in inputs + ordered):
            return "emitted an ordering over unparseable input"
        if len(inputs) != len(ordered):
            return f"ordering lost elements: {len(inputs)} in, {len(ordered)} out"
        for previous, current in zip(ordered, ordered[1:]):
            if previous > current:
                return f"ascending order violated at {str(previous)!r} > {str(current)!r}"
        if Counter(map(str, inputs)) != Counter(map(str, ordered)):
            return "ordering is not a permutation of its input"
        return None

    raise ProtocolError(f"unknown record kind {kind!r}")


def _toml_shape(value: object) -> str:
    """A type-tagged rendering of a parsed TOML document.

    Type tags matter: `True == 1` and `1 == 1.0` in Python, so a plain `==`
    would let a re-serialization turn a boolean into an integer unnoticed.
    Both sides of this comparison are Python values, so the float formatting
    here is never compared against MoonBit's.
    """
    if isinstance(value, bool):
        return "bool:" + ("true" if value else "false")
    if isinstance(value, int):
        return "int:" + str(value)
    if isinstance(value, float):
        return "float:" + repr(value)
    if isinstance(value, str):
        return "str:" + value
    if isinstance(value, (list, tuple)):
        return "array:[" + ",".join(_toml_shape(item) for item in value) + "]"
    if isinstance(value, dict):
        # TOML tables are unordered maps, and a re-serialization has to move
        # plain values ahead of sub-tables so that header scoping cannot capture
        # a sibling key, so the comparison sorts keys. Arrays stay positional.
        return (
            "table:{"
            + ",".join(
                f"{key}={_toml_shape(value[key])}" for key in sorted(value)
            )
            + "}"
        )
    if hasattr(value, "isoformat"):
        return "datetime:" + str(value)
    return f"other:{type(value).__name__}"


def _any_filename_parser_accepts(raw: str) -> bool:
    """True when either packaging filename parser accepts `raw`."""
    for parser, error in (
        (parse_wheel_filename, InvalidWheelFilename),
        (parse_sdist_filename, InvalidSdistFilename),
    ):
        try:
            parser(raw)
            return True
        except (error, InvalidVersion):
            continue
    return False


def classify_difference(oracle: "Oracle", parts: list[str]) -> str:
    """Bucket a difference so a report can say *why* two implementations differ.

    The library targets one ``packaging`` release. When another release
    disagrees, the cause is one of three upstream changes this project
    documents, and naming it keeps the drift table actionable instead of just
    counting rows:

    ``auto-prerelease-admission``
        the "no final candidate, so admit prereleases" rule. Detected exactly:
        the difference disappears when prereleases are forced on, so the two
        implementations only disagree about the *automatic* policy. This was
        extended in packaging 26.0.
    ``exclusive-ordered-comparison``
        `<` and `>` used to be implemented with special cases and became
        explicit version ranges in packaging 26.3.
    ``compatible-release-range``
        the upper bound of `~=` was computed differently before 26.3.

    The remaining buckets name the record kind. Detection is best effort: a
    record is attributed to the first bucket that explains it, most specific
    rule first.
    """
    kind = parts[1]
    if kind == "contains" and parts[2] != "any":
        spec = oracle.specifier_set(parts[3])
        version = oracle.version(parts[4])
        if spec is not None and version is not None:
            forced = str(spec.contains(version, prereleases=True)).lower()
            if forced == parts[5]:
                return "auto-prerelease-admission"
    if kind == "filter" and parts[2] != "any":
        spec = oracle.specifier_set(parts[3])
        candidates = [oracle.version(item) for item in parts[4].split("|")]
        if spec is not None and all(item is not None for item in candidates):
            forced = "|".join(str(item) for item in spec.filter(candidates, prereleases=True))
            if forced == parts[5]:
                return "auto-prerelease-admission"
    if kind in ("contains", "filter"):
        constraint = parts[3]
        if "~=" in constraint:
            return "compatible-release-range"
        if "<" in constraint or ">" in constraint:
            return "exclusive-ordered-comparison"
        return "unclassified"
    if kind == "canon":
        return "name-normalization" if parts[2] == "name" else "version-key-form"
    if kind == "file":
        return "filename-grammar"
    if kind == "req":
        return "requirement-grammar"
    if kind == "marker":
        return "marker-grammar"
    if kind == "marker_eval":
        return "marker-evaluation"
    if kind == "marker_env":
        return "marker-environment"
    if kind == "toml":
        return "toml-grammar"
    if kind == "license":
        return "license-expression"
    return {"parse": "version-grammar", "spec": "specifier-grammar"}.get(kind, "ordering")


# Marker fields are escaped by the emitter because a marker value may contain a
# tab or a newline once its quotes are decoded.
ESCAPED_FIELDS = {
    "marker": (2, 4),
    "marker_eval": (3, 5),
    "toml": (3, 5),
    "license": (2, 4),
}


# Error-kind equivalences. `packaging` collapses several distinct marker
# evaluation failures into one exception type; the library keeps them apart so a
# caller can tell them apart, so the comparison maps its finer-grained names
# onto the oracle's coarser ones. `SetValuedOnLeft` is exactly the condition
# packaging reports as `UndefinedComparison` ("Set-valued marker 'extras' can
# only be used with the membership form ...").
EQUIVALENT_ERROR_KINDS = {
    "SetValuedOnLeft": "UndefinedComparison",
}


def unescape_record(text: str) -> str:
    """Undo `escape_record` in the emitter."""
    if "\\" not in text:
        return text
    out = []
    index = 0
    while index < len(text):
        char = text[index]
        if char != "\\" or index + 1 >= len(text):
            out.append(char)
            index += 1
            continue
        following = text[index + 1]
        if following == "\\":
            out.append("\\")
        elif following == "t":
            out.append("\t")
        elif following == "n":
            out.append("\n")
        elif following == "r":
            out.append("\r")
        else:
            out.append(char)
            index += 1
            continue
        index += 2
    return "".join(out)


def parse_record(line: str) -> tuple[str, str, str, list[str]]:
    """Validate a record's shape and return (source, kind, mode, fields).

    The returned fields have the emitter's escaping undone, so they are the
    values the oracle should see even when one of them contains a tab.
    """
    parts = line.split("\t")
    if len(parts) < 2:
        raise ProtocolError(f"record without kind: {line[:80]!r}")
    source, kind = parts[0], parts[1]
    if kind not in ARITY:
        raise ProtocolError(f"unknown record kind {kind!r} in {line[:80]!r}")
    if len(parts) != ARITY[kind]:
        raise ProtocolError(
            f"{kind} record has {len(parts)} fields, expected {ARITY[kind]}: {line[:80]!r}"
        )
    for index in ESCAPED_FIELDS.get(kind, ()):
        parts[index] = unescape_record(parts[index])
    mode = parts[2] if kind in ("contains", "filter") else "-"
    if mode != "-" and mode not in MODES:
        raise ProtocolError(f"unknown prerelease mode {mode!r}")
    return source, kind, mode, parts


def emitter_command(args) -> list[str]:
    moon = args.moon or shutil.which("moon") or str(Path.home() / ".moon" / "bin" / "moon")
    return [moon, "run", "examples/diff", "--target", args.target]


def run_emitter(args) -> tuple[str, float]:
    root = Path(__file__).resolve().parents[1]
    env = dict(os.environ)
    env["PATH"] = f"{Path.home() / '.moon' / 'bin'}{os.pathsep}{env.get('PATH', '')}"
    command = emitter_command(args)
    started = time.time()
    completed = subprocess.run(
        command,
        cwd=root,
        capture_output=True,
        env=env,
        check=False,
    )
    elapsed = time.time() - started
    if completed.returncode != 0:
        sys.stderr.write(completed.stderr.decode("utf-8", "replace"))
        raise SystemExit(f"emitter failed: {' '.join(command)}")
    return completed.stdout.decode("utf-8", "replace"), elapsed


def load_records(text: str):
    """Yield every non-empty record line, unparsed."""
    for line in text.splitlines():
        if line:
            yield line


def summarize(counters: Counter, width: int = 28) -> str:
    rows = sorted(counters.items())
    if not rows:
        return "  none"
    out = []
    for key, value in rows:
        label = key if isinstance(key, str) else "/".join(key)
        out.append(f"  {label:<{width}} {value}")
    return "\n".join(out)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--target", default="js", choices=["js", "wasm", "wasm-gc", "native"])
    parser.add_argument("--moon", default=None, help="path to the moon executable")
    parser.add_argument("--input", default=None, help="replay a captured corpus instead of running moon")
    parser.add_argument("--capture", default=None, help="write the emitter output to this file")
    parser.add_argument(
        "--capture-only",
        action="store_true",
        help="write the corpus and exit without comparing against the oracle",
    )
    parser.add_argument("--json", default=None, help="write a machine readable report here")
    parser.add_argument("--oracle-version", default=None, help="require this packaging version")
    parser.add_argument(
        "--pinned-oracle",
        default="26.3",
        help="packaging release the library targets; differences on other releases "
        "stop being fatal when --tolerate-drift is passed",
    )
    parser.add_argument(
        "--tolerate-drift",
        "--tolerate-policy-drift",
        dest="tolerate_drift",
        action="store_true",
        help="treat every difference as tolerated drift instead of a failure; use "
        "this only when the oracle is not the release the library targets",
    )
    parser.add_argument("--max-samples", type=int, default=5, help="samples kept per group")
    args = parser.parse_args(argv)

    if args.oracle_version and ORACLE_VERSION != args.oracle_version:
        print(
            f"oracle mismatch: packaging {ORACLE_VERSION} installed, "
            f"{args.oracle_version} required",
            file=sys.stderr,
        )
        return EXIT_ERROR

    if args.input:
        text = Path(args.input).read_text(encoding="utf-8")
        emitter_seconds = float("nan")
    else:
        text, emitter_seconds = run_emitter(args)
    if args.capture:
        Path(args.capture).write_text(text, encoding="utf-8")

    if args.capture_only:
        print(f"captured {len(text.splitlines())} records to {args.capture}")
        return EXIT_OK

    oracle = Oracle()
    cases: Counter = Counter()
    mismatches: Counter = Counter()
    drift: Counter = Counter()
    causes: Counter = Counter()
    samples: dict[tuple[str, str, str], list[str]] = defaultdict(list)
    drift_samples: dict[tuple[str, str, str], list[str]] = defaultdict(list)
    records = 0
    prerelease_cases = 0
    drift_is_expected = args.tolerate_drift and ORACLE_VERSION != args.pinned_oracle

    try:
        for line in load_records(text):
            source, kind, mode, parts = parse_record(line)
            records += 1
            cases[(source, kind, mode)] += 1
            if mode != "-":
                prerelease_cases += 1
            problem = check_record(oracle, parts)
            if problem is None:
                continue
            key = (source, kind, mode)
            causes[classify_difference(oracle, parts)] += 1
            if drift_is_expected:
                drift[key] += 1
                if len(drift_samples[key]) < args.max_samples:
                    drift_samples[key].append(problem)
            else:
                mismatches[key] += 1
                if len(samples[key]) < args.max_samples:
                    samples[key].append(problem)
    except ProtocolError as error:
        print(f"protocol error: {error}", file=sys.stderr)
        return EXIT_ERROR

    total_cases = sum(cases.values())
    total_mismatches = sum(mismatches.values())
    total_drift = sum(drift.values())
    total_differences = total_mismatches + total_drift

    print(
        f"oracle: packaging {ORACLE_VERSION} (python {sys.version.split()[0]}), "
        f"library targets packaging {args.pinned_oracle}"
    )
    print(
        f"toml reference reader: "
        f"{'none (toml records will not be checked)' if toml_reader is None else toml_reader.__name__}"
    )
    print(f"target: {args.target}" + ("" if args.input else f", emitter {emitter_seconds:.1f}s"))
    print(f"records: {total_cases} ({prerelease_cases} with a prerelease mode)")
    print(
        f"distinct versions accepted by the oracle: {oracle.accepted_versions()}; "
        f"distinct specifier sets: {oracle.accepted_specifier_sets()}"
    )

    print("\nrecords per source and kind:")
    per_source: Counter = Counter()
    for (source, kind, _mode), value in cases.items():
        per_source[(source, kind)] += value
    print(summarize(per_source, width=24))

    print("\nmismatches per source, kind and mode:")
    print(summarize(mismatches))

    if drift:
        print(
            f"\ndifferences tolerated on packaging {ORACLE_VERSION} "
            f"(the library targets {args.pinned_oracle}); by cause:"
        )
        print(summarize(causes))
        print("by source, kind and mode:")
        print(summarize(drift))

    if samples:
        print("\nsamples:")
        for key in sorted(samples):
            print(f"  {key[0]}/{key[1]}/{key[2]}:")
            for item in samples[key]:
                print(f"    - {item}")

    if drift_samples:
        print("\ndrift samples:")
        for key in sorted(drift_samples):
            print(f"  {key[0]}/{key[1]}/{key[2]}:")
            for item in drift_samples[key]:
                print(f"    - {item}")

    if args.json:
        report = {
            "oracle_version": ORACLE_VERSION,
            "pinned_oracle": args.pinned_oracle,
            "python_version": sys.version.split()[0],
            "toml_reader": None if toml_reader is None else toml_reader.__name__,
            "target": args.target,
            "emitter_seconds": None if args.input else round(emitter_seconds, 3),
            "records": total_cases,
            "records_with_prerelease_mode": prerelease_cases,
            "distinct_versions_accepted": oracle.accepted_versions(),
            "distinct_specifier_sets_accepted": oracle.accepted_specifier_sets(),
            "records_per_source_kind": {
                f"{source}/{kind}": value for (source, kind), value in sorted(per_source.items())
            },
            "mismatches": {"/".join(key): value for key, value in sorted(mismatches.items())},
            "policy_drift": {"/".join(key): value for key, value in sorted(drift.items())},
            "difference_total": total_differences,
            "mismatch_total": total_mismatches,
            "policy_drift_total": total_drift,
            "policy_drift_causes": dict(sorted(causes.items())),
            "mismatch_samples": {"/".join(key): value for key, value in sorted(samples.items())},
            "policy_drift_samples": {
                "/".join(key): value for key, value in sorted(drift_samples.items())
            },
        }
        Path(args.json).write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print(f"\nreport written to {args.json}")

    if total_mismatches:
        print(f"\nFAILED: {total_mismatches} mismatches against packaging {ORACLE_VERSION}")
        return EXIT_MISMATCH
    print(f"\nOK: {total_cases} records agree with packaging {ORACLE_VERSION}")
    return EXIT_OK


if __name__ == "__main__":
    raise SystemExit(main())
