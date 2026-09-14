#!/usr/bin/env python3
"""Build the PEP 751 corpus used by the differential corpus.

Three kinds of document are collected:

- curated `pylock.toml` documents under `pylock_cases/`, one rule at a time,
  written from the specification's own sections -- including the example the PEP
  prints, verbatim;
- documents *derived* from the real PEP 691 index responses embedded in
  `fixtures/index_corpus.mbt`: one lock file per project, whose file records
  (name, URL, sha256, size, upload time) are the index's own. The documents are
  constructed here; no `pylock.toml` is fetched from anywhere, and none exists to
  fetch -- what is real is the index response behind each file record;
- single-edit mutations of the accepted documents, kept only when the
  specification rejects them.

PyPA `packaging` is used for two things it genuinely knows: PEP 508 marker syntax
and evaluation (`packaging.markers`), PEP 440 versions and specifier sets, and
`canonicalize_name`. Everything else is a second reading of PEP 751, written from
the specification in `reference_pylock` below, exactly as `project_document` in
`fetch_index_corpus.py` is a second reading of PEP 691. That projection is what
the emitter's `pylock` records are compared against, so the rules live in one
place and both sides have to agree with them.

Two things in here are deliberately *not* rules, and the corpus says so rather
than pretending otherwise:

- PEP 685 normalization of an `extras`, `dependency-groups`, `default-groups` or
  dependency `extras` entry is a writer's job; PEP 751 does not require the file to
  spell a name in normalized form, so the reference checks the name syntax only and
  leaves the comparison to `canonicalize_name`. An unnormalized spelling is an
  accepted document on both sides.
- The install algorithm's singularity rule (narrowing several entries for one name
  down to one per target) is not implemented by the library and not modelled here.

A reader has to be told which parts of the comparison are external and which are
ours, so: the verdicts and the projection for PEP 751 are *ours*, not an
independent implementation's. They catch a library that has drifted from the
specification as this file reads it; they cannot catch the specification being
read the same way twice.

Run with any Python 3.8+ interpreter that has `tomli` (or 3.11+, which has
`tomllib`)::

    python3 -B tools/fetch_pylock_corpus.py

No network access is needed or performed.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

from packaging.markers import InvalidMarker, Marker
from packaging.specifiers import InvalidSpecifier, SpecifierSet
from packaging.utils import canonicalize_name
from packaging.version import InvalidVersion, Version

# A TOML reader is needed to re-derive the projection from a document, so a
# missing one is fatal here rather than a silent downgrade. `diff_packaging.py`
# imports this module, which means a harness run on an interpreter without a
# reader stops with this message instead of reporting every `pylock` record as a
# difference -- the same stance `fetch_toml_corpus.py` takes.
try:
    import tomli as toml_reader
except ImportError:  # pragma: no cover - Python 3.11+ has tomllib
    try:
        import tomllib as toml_reader
    except ImportError:  # pragma: no cover - Python 3.10 without tomli
        raise SystemExit(
            "a TOML reader is required: use Python 3.11+, or install `tomli` "
            "in the interpreter that runs the harness"
        ) from None

ROOT = Path(__file__).resolve().parents[1]
CASES = ROOT / "pylock_cases"
MBT = ROOT / "fixtures" / "pylock_corpus.mbt"
JSON_OUT = ROOT / "fixtures" / "pylock_corpus.json"
INDEX_FIXTURE = ROOT / "fixtures" / "index_corpus.mbt"

# The environment both sides decide package applicability in. `extra` is the
# single-valued key PEP 508 defines; `extras` and `dependency_groups` are the
# set-valued keys PEP 751 adds to the marker vocabulary.
ENVIRONMENT = [
    ("sys_platform", "linux"),
    ("os_name", "posix"),
    ("platform_system", "Linux"),
    ("platform_machine", "x86_64"),
    ("platform_release", "6.1.0"),
    ("platform_version", "#1 SMP"),
    ("platform_python_implementation", "CPython"),
    ("implementation_name", "cpython"),
    ("python_version", "3.11"),
    ("python_full_version", "3.11.9"),
    ("implementation_version", "3.11.9"),
    ("extra", ""),
]

ENVIRONMENT_SETS = [("extras", []), ("dependency_groups", [])]

# The version-control systems PEP 751 names.
VCS_TYPES = ("git", "hg", "bzr", "svn")

# A project name, the PEP 508 grammar's spelling of it.
NAME_PATTERN = re.compile(r"^([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9._-]*[A-Za-z0-9])$")

# Two versions and at most this many file records per version are taken from each
# real index response, so one derived document stays readable and the fixture
# stays a corpus rather than a copy of PyPI.
MAX_DERIVED_VERSIONS = 3
MAX_DERIVED_FILES = 6


def mbt_string(text: str) -> str:
    """Render `text` as a MoonBit string literal."""
    out = ['"']
    for char in text:
        if char == "\\":
            out.append("\\\\")
        elif char == '"':
            out.append('\\"')
        elif char == "\n":
            out.append("\\n")
        elif char == "\r":
            out.append("\\r")
        elif char == "\t":
            out.append("\\t")
        elif ord(char) < 0x20 or ord(char) == 0x7F:
            # MoonBit treats the vertical tab and the form feed as line breaks, so
            # a raw one would end the literal and turn the rest into source.
            out.append("\\u{%x}" % ord(char))
        else:
            out.append(char)
    out.append('"')
    return "".join(out)


# --- the reference implementation -------------------------------------------


class Rejected(Exception):
    """A document the specification rejects, with the reason."""


def _table(value: object, where: str, required: bool = True) -> dict | None:
    if value is None:
        if required:
            raise Rejected(f"{where} is required")
        return None
    if not isinstance(value, dict):
        raise Rejected(f"{where} must be a table")
    return value


def _text(value: object, where: str, required: bool = False, non_empty: bool = True):
    if value is None:
        if required:
            raise Rejected(f"{where} is required")
        return None
    if not isinstance(value, str):
        raise Rejected(f"{where} must be a string")
    if non_empty and not value:
        raise Rejected(f"{where} must not be empty")
    return value


def _string_list(value: object, where: str, validate=None) -> list[str]:
    if value is None:
        return []
    if not isinstance(value, list):
        raise Rejected(f"{where} must be an array of strings")
    out = []
    for item in value:
        item = _text(item, where)
        if validate is not None:
            validate(item, where)
        out.append(item)
    return out


def _name(value: object, where: str) -> str:
    text = _text(value, where, required=True)
    if not NAME_PATTERN.match(text):
        raise Rejected(f"{where} is not a valid project name")
    return text


def _extra_name(value: object, where: str) -> str:
    """An extra or dependency-group name.

    Only the name syntax is checked, not the spelling: PEP 685 normalization is
    something a writer does, PEP 751 does not require the file to already be
    normalized, and both implementations here compare names with
    `canonicalize_name` instead of demanding one spelling. `_name` is where the
    syntax rule lives, so this is deliberately the same predicate.
    """
    return _name(value, where)


def _version(value: object, where: str) -> str:
    text = _text(value, where, required=True)
    try:
        return str(Version(text))
    except InvalidVersion as error:
        raise Rejected(f"{where} is not a PEP 440 version: {error}") from error


def _specifier_set(value: object, where: str):
    text = _text(value, where)
    if text is None:
        return None
    try:
        return SpecifierSet(text)
    except InvalidSpecifier as error:
        raise Rejected(f"{where} is not a specifier set: {error}") from error


def _marker(value: object, where: str) -> str | None:
    text = _text(value, where)
    if text is None:
        return None
    try:
        Marker(text)
    except InvalidMarker as error:
        raise Rejected(f"{where} is not a marker: {error}") from error
    return text


def _hashes(value: object, where: str) -> dict[str, str]:
    if value is None:
        raise Rejected(f"{where}.hashes is required")
    table = _table(value, f"{where}.hashes")
    if not table:
        raise Rejected(f"{where}.hashes must not be empty")
    for algorithm, digest in table.items():
        _text(algorithm, f"{where}.hashes key")
        _text(digest, f"{where}.hashes value", required=True)
    return table


def _file_record(record: object, where: str, hashes_required: bool) -> dict:
    table = _table(record, where)
    if table.get("name") is not None:
        _text(table["name"], f"{where}.name")
    for key in ("url", "path"):
        if table.get(key) is not None:
            _text(table[key], f"{where}.{key}")
    if not any(table.get(key) for key in ("name", "url", "path")):
        raise Rejected(
            f"{where} has no name, url or path to be found under"
        )
    if hashes_required or table.get("hashes") is not None:
        _hashes(table.get("hashes"), where)
    if table.get("size") is not None:
        size = table["size"]
        if not isinstance(size, int) or isinstance(size, bool) or size < 0:
            raise Rejected(f"{where}.size must be a non-negative integer")
    if table.get("upload-time") is not None:
        stamp = table["upload-time"]
        if not hasattr(stamp, "tzinfo"):
            raise Rejected(f"{where}.upload-time must be a datetime")
        offset = stamp.utcoffset() if stamp.tzinfo is not None else None
        if offset is None or offset.total_seconds() != 0:
            raise Rejected(f"{where}.upload-time must be recorded in UTC")
    if table.get("subdirectory") is not None:
        _text(table["subdirectory"], f"{where}.subdirectory")
    return table


def _vcs(table: dict, where: str) -> None:
    kind = _text(table.get("type"), f"{where}.type", required=True)
    if kind not in VCS_TYPES:
        raise Rejected(f"{where}.type must be one of {', '.join(VCS_TYPES)}")
    url = _text(table.get("url"), f"{where}.url")
    path = _text(table.get("path"), f"{where}.path")
    if url is None and path is None:
        raise Rejected(f"{where} needs a url or a path")
    _text(table.get("commit-id"), f"{where}.commit-id", required=True)
    if table.get("requested-revision") is not None:
        _text(table["requested-revision"], f"{where}.requested-revision")
    if table.get("subdirectory") is not None:
        _text(table["subdirectory"], f"{where}.subdirectory")


def _dependency(entry: object, package_name: str, where: str) -> None:
    table = _table(entry, where)
    name = _name(table.get("name"), f"{where}.name")
    if canonicalize_name(name) == canonicalize_name(package_name):
        raise Rejected(f"{where} names the package it is recorded on")
    if table.get("version") is not None:
        _version(table["version"], f"{where}.version")
    _marker(table.get("marker"), f"{where}.marker")
    _string_list(table.get("extras"), f"{where}.extras", _extra_name)


def _package(entry: object, ordinal: int) -> dict:
    where = f"packages[{ordinal}]"
    table = _table(entry, where)
    name = _name(table.get("name"), f"{where}.name")
    # The members each source form is "mutually-exclusive" with, per the
    # specification's own `Required?` lines: the file lists conflict with a direct
    # reference, and two direct references conflict with each other. `index`
    # combines with anything.
    direct = [
        key
        for key in ("vcs", "directory", "archive", "path")
        if table.get(key) is not None
    ]
    lists = [
        key for key in ("files", "wheels", "sdist") if table.get(key) is not None
    ]
    if len(direct) > 1 or (direct and lists):
        raise Rejected(
            f"{where} records conflicting sources: {', '.join(direct + lists)}"
        )
    # `packages.version` is optional, and forbidden when a *source tree* is
    # recorded, because a source tree has no version that can be guaranteed --
    # which is a different thing from an archive, whose file has one.
    source_tree = table.get("vcs") is not None or table.get("directory") is not None
    if table.get("version") is not None:
        if source_tree:
            raise Rejected(
                f"{where}.version must not be recorded next to a source tree"
            )
        _version(table["version"], f"{where}.version")
    _marker(table.get("marker"), f"{where}.marker")
    _specifier_set(table.get("requires-python"), f"{where}.requires-python")
    if table.get("index") is not None:
        _text(table["index"], f"{where}.index")
    dependencies = table.get("dependencies")
    if dependencies is not None:
        if not isinstance(dependencies, list):
            raise Rejected(f"{where}.dependencies must be an array of tables")
        for index, item in enumerate(dependencies):
            _dependency(item, name, f"{where}.dependencies[{index}]")
    if table.get("vcs") is not None:
        _vcs(_table(table["vcs"], f"{where}.vcs"), f"{where}.vcs")
    if table.get("directory") is not None:
        directory = _table(table["directory"], f"{where}.directory")
        _text(directory.get("path"), f"{where}.directory.path", required=True)
        if directory.get("editable") is not None and not isinstance(
            directory["editable"], bool
        ):
            raise Rejected(f"{where}.directory.editable must be a boolean")
    if table.get("archive") is not None:
        _file_record(table["archive"], f"{where}.archive", True)
    if table.get("sdist") is not None:
        _file_record(table["sdist"], f"{where}.sdist", True)
    wheels = table.get("wheels")
    if wheels is not None:
        if not isinstance(wheels, list):
            raise Rejected(f"{where}.wheels must be an array of tables")
        for index, item in enumerate(wheels):
            _file_record(item, f"{where}.wheels[{index}]", True)
    files = table.get("files")
    if files is not None:
        if not isinstance(files, list):
            raise Rejected(f"{where}.files must be an array of tables")
        for index, item in enumerate(files):
            _file_record(item, f"{where}.files[{index}]", True)
    return table


def reference_pylock(document: str) -> tuple[bool, str, str | None]:
    """The specification's answer for one document.

    Returns `(accepted, reason, projection)`. A reader that supports the major
    version but not the minor one is told to *warn*, so an unknown
    `lock-version` is accepted here and rejected by the library -- that is one of
    the declared divergences, and it is asserted in both directions rather than
    tolerated.
    """
    try:
        parsed = toml_reader.loads(document)
    except Exception as error:  # noqa: BLE001 - the reader reports its own diagnosis
        return False, f"not TOML: {type(error).__name__}: {error}", None
    try:
        if not isinstance(parsed, dict):
            raise Rejected("the document must be a table")
        lock_version = _text(parsed.get("lock-version"), "lock-version", required=True)
        if not re.match(r"^\d+\.\d+$", lock_version):
            raise Rejected("lock-version must be MAJOR.MINOR")
        _string_list(parsed.get("environments"), "environments", _marker)
        _specifier_set(parsed.get("requires-python"), "requires-python")
        _string_list(parsed.get("extras"), "extras", _extra_name)
        _string_list(parsed.get("dependency-groups"), "dependency-groups", _extra_name)
        _string_list(parsed.get("default-groups"), "default-groups", _extra_name)
        _text(parsed.get("created-by"), "created-by", required=True)
        packages = parsed.get("packages")
        if packages is None:
            raise Rejected("packages is required")
        if not isinstance(packages, list):
            raise Rejected("packages must be an array of tables")
        for ordinal, entry in enumerate(packages):
            _package(entry, ordinal)
    except Rejected as error:
        return False, str(error), None
    return True, "", projection(document)


# --- the projection ----------------------------------------------------------


def _optional(value: object) -> str:
    return value if value else "-"


def _listing(items: list[str]) -> str:
    return str(len(items)) + "".join("^" + item for item in items)


def _last_component(text: str) -> str | None:
    tail = text.split("/")[-1]
    for separator in ("#", "?"):
        if separator in tail:
            tail = tail.split(separator)[0]
    return tail or None


def _filename_of(record: dict) -> str | None:
    name = record.get("name")
    if name:
        return name
    for key in ("url", "path"):
        value = record.get(key)
        if value:
            tail = _last_component(value)
            if tail:
                return tail
    return None


UPLOAD_TIME = re.compile(r"upload-time\s*=\s*([^,\n}\]]+)")


def upload_times(document: str) -> list[str]:
    """Every `upload-time` value, as the document spells it.

    `tomli` returns a `datetime`, and the library records the *source spelling*,
    which differs for `Z` and for the space-separated form. The spellings used by
    this corpus are the ones `tomli` accepts and re-emits unchanged, and the
    count is asserted against the records that carry one, so the comparison can
    never silently pair the wrong stamp with the wrong record.
    """
    return [match.group(1).strip() for match in UPLOAD_TIME.finditer(document)]


def projection(document: str) -> str:
    """The values a reader extracted, in the form the emitter has to produce."""
    parsed = toml_reader.loads(document)
    stamps = upload_times(document)
    used = 0
    out = ["lock-version=" + parsed["lock-version"]]
    out.append(";environments=" + _listing(parsed.get("environments", [])))
    out.append(";requires-python=" + _optional(parsed.get("requires-python")))
    out.append(";extras=" + _listing(parsed.get("extras", [])))
    out.append(";dependency-groups=" + _listing(parsed.get("dependency-groups", [])))
    out.append(";default-groups=" + _listing(parsed.get("default-groups", [])))
    out.append(";created-by=" + _optional(parsed.get("created-by")))
    packages = parsed.get("packages", [])
    out.append(";packages=" + str(len(packages)))
    environment = dict(ENVIRONMENT)
    for key, values in ENVIRONMENT_SETS:
        environment[key] = values
    for ordinal, package in enumerate(packages):
        marker = package.get("marker")
        applies = "1"
        if marker:
            try:
                applies = "1" if Marker(marker).evaluate(environment) else "0"
            except Exception:  # noqa: BLE001 - a key the environment cannot answer
                applies = "!"
        group = "|pkg%d:name=%s" % (ordinal, package["name"])
        group += ";version=" + (str(Version(package["version"])) if package.get("version") else "-")
        group += ";marker=" + _optional(marker)
        group += ";applies=" + applies
        group += ";requires-python=" + _optional(package.get("requires-python"))
        group += ";deps=" + str(len(package.get("dependencies", [])))
        group += ";files=" + str(len(package.get("files", [])))
        group += ";wheels=" + str(len(package.get("wheels", [])))
        group += ";sdist=" + ("1" if package.get("sdist") is not None else "0")
        group += ";archive=" + ("1" if package.get("archive") is not None else "0")
        group += ";vcs=" + ("1" if package.get("vcs") is not None else "0")
        group += ";directory=" + ("1" if package.get("directory") is not None else "0")
        group += ";index=" + _optional(package.get("index"))
        group += ";path=" + ("1" if package.get("path") is not None else "0")
        ordered = [("files", item) for item in package.get("files", [])]
        if package.get("sdist") is not None:
            ordered.append(("sdist", package["sdist"]))
        ordered += [("wheels", item) for item in package.get("wheels", [])]
        if package.get("archive") is not None:
            ordered.append(("archive", package["archive"]))
        group += ";all-files=" + str(len(ordered))
        out.append(group)
        for index, dependency in enumerate(package.get("dependencies", [])):
            text = "|dep%d.%d:name=%s" % (ordinal, index, dependency["name"])
            text += ";version=" + (
                str(Version(dependency["version"])) if dependency.get("version") else "-"
            )
            text += ";marker=" + _optional(dependency.get("marker"))
            text += ";extras=" + _listing(dependency.get("extras", []))
            out.append(text)
        for index, (kind, record) in enumerate(ordered):
            digest = (record.get("hashes") or {}).get("sha256")
            stamp = "-"
            if record.get("upload-time") is not None:
                if used >= len(stamps):
                    raise AssertionError("more upload-time members than spellings")
                stamp = stamps[used]
                used += 1
            text = "|file%d.%d:kind=%s" % (ordinal, index, kind)
            text += ";filename=" + _optional(_filename_of(record))
            text += ";sha256=" + _optional(digest)
            text += ";size=" + (
                str(record["size"]) if record.get("size") is not None else "-"
            )
            text += ";upload-time=" + stamp
            text += ";subdirectory=" + _optional(record.get("subdirectory"))
            out.append(text)
    if used != len(stamps):
        raise AssertionError("an upload-time spelling was not matched to a record")
    return "".join(out)


# --- curated documents -------------------------------------------------------

LOCK_PREFIX = 'lock-version = "1.0"\ncreated-by = "moon-pyversion corpus"\n'


def wheel(name: str, url: str, sha: str, **extra) -> str:
    body = ['name = "%s"' % name, 'url = "%s"' % url]
    for key, value in extra.items():
        body.append("%s = %s" % (key, value))
    body.append('hashes = { sha256 = "%s" }' % sha)
    return "{ " + ", ".join(body) + " }"


def curated() -> list[tuple[str, str]]:
    """Accepted documents, as `(case name, document)`."""
    cases: list[tuple[str, str]] = []

    cases.append(("01_pep751_example", PEP751_EXAMPLE))
    # A package entry with no source member: every source form is `Required?: no`
    # in the specification and the mutually-exclusive rule only forbids two of
    # them, so a version-only entry is well formed. It is unusual -- nothing says
    # where the distribution is -- and it is here because "the specification does
    # not forbid it" and "the reader should reject it" are different claims.
    cases.append(
        (
            "00_package_without_a_source",
            LOCK_PREFIX + '\n[[packages]]\nname = "spam"\nversion = "1.0"\n',
        )
    )
    cases.append(
        (
            "02_minimal",
            'lock-version = "1.0"\ncreated-by = "mousebender"\npackages = []\n',
        )
    )
    cases.append(
        (
            "03_vcs_url",
            LOCK_PREFIX
            + """
[[packages]]
name = "attrs"
[packages.vcs]
type = "git"
url = "https://github.com/python-attrs/attrs.git"
requested-revision = "main"
commit-id = "0f1e2d3c4b5a69788796a5b4c3d2e1f009182736"
subdirectory = "src"
""",
        )
    )
    cases.append(
        (
            "04_vcs_path",
            LOCK_PREFIX
            + """
[[packages]]
name = "spam"
[packages.vcs]
type = "hg"
path = "../spam"
commit-id = "deadbeef"
""",
        )
    )
    cases.append(
        (
            "05_directory",
            LOCK_PREFIX
            + """
[[packages]]
name = "spam"
[packages.directory]
path = "../spam"
editable = false
""",
        )
    )
    cases.append(
        (
            "06_archive",
            LOCK_PREFIX
            + """
[[packages]]
name = "spam"
version = "1.0"
[packages.archive]
url = "https://example.invalid/spam-1.0.tar.gz"
size = 12345
hashes = { sha256 = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef" }
subdirectory = "spam-1.0"
""",
        )
    )
    cases.append(
        (
            "07_sdist_and_wheels",
            LOCK_PREFIX
            + """
[[packages]]
name = "cattrs"
version = "24.1.2"
requires-python = ">=3.8"
index = "https://pypi.org/simple/"
[packages.sdist]
name = "cattrs-24.1.2.tar.gz"
url = "https://files.invalid/cattrs-24.1.2.tar.gz"
size = 55000
hashes = { sha256 = "aaaa", md5 = "bbbb" }
[[packages.wheels]]
name = "cattrs-24.1.2-py3-none-any.whl"
url = "https://files.invalid/cattrs-24.1.2-py3-none-any.whl"
upload-time = 2025-01-25T11:30:10.164985+00:00
hashes = { sha256 = "cccc" }
[[packages.wheels]]
url = "https://files.invalid/cattrs-24.1.2-cp311-cp311-manylinux_2_17_x86_64.whl"
hashes = { sha256 = "dddd" }
""",
        )
    )
    cases.append(
        (
            "08_files_draft",
            LOCK_PREFIX
            + """
[[packages]]
name = "spam"
version = "1.0"
[[packages.files]]
name = "spam-1.0.tar.gz"
path = "wheels/spam-1.0.tar.gz"
hashes = { sha256 = "eeee" }
""",
        )
    )
    cases.append(
        (
            "09_package_path_draft",
            LOCK_PREFIX
            + """
[[packages]]
name = "spam"
version = "1.0"
path = "vendor/spam"
""",
        )
    )
    cases.append(
        (
            "10_environments",
            'lock-version = "1.0"\nenvironments = ["sys_platform == \'win32\'", "sys_platform == \'linux\' and python_version >= \'3.9\'", "python_full_version === \'3.11.9\'"]\ncreated-by = "mousebender"\npackages = []\n',
        )
    )
    cases.append(
        (
            "11_requires_python",
            'lock-version = "1.0"\nrequires-python = ">=3.9,<4"\ncreated-by = "mousebender"\npackages = []\n',
        )
    )
    cases.append(
        (
            "12_extras_and_groups",
            'lock-version = "1.0"\nextras = ["docs", "test"]\ndependency-groups = ["lint", "typecheck"]\ndefault-groups = ["lint"]\ncreated-by = "mousebender"\npackages = []\n',
        )
    )
    cases.append(
        (
            "13_marker_on_package",
            LOCK_PREFIX
            + """
[[packages]]
name = "colorama"
version = "0.4.6"
marker = "sys_platform == 'win32'"

[[packages]]
name = "colorama"
version = "0.4.6"
marker = "sys_platform != 'win32'"
""",
        )
    )
    cases.append(
        (
            "14_marker_needs_an_unanswerable_key",
            LOCK_PREFIX
            + """
[[packages]]
name = "spam"
version = "1.0"
marker = "os_name == 'nt' and platform_release > '2'"
""",
        )
    )
    cases.append(
        (
            "15_package_requires_python",
            LOCK_PREFIX
            + """
[[packages]]
name = "numpy"
version = "2.2.3"
requires-python = ">=3.10"
[[packages.wheels]]
name = "numpy-2.2.3-cp311-cp311-manylinux_2_17_x86_64.whl"
url = "https://files.invalid/numpy-2.2.3-cp311-cp311-manylinux_2_17_x86_64.whl"
hashes = { sha256 = "ffff" }
""",
        )
    )
    cases.append(
        (
            "16_dependencies",
            LOCK_PREFIX
            + """
[[packages]]
name = "flask"
version = "3.1.0"
dependencies = [
  { name = "click", version = "8.1.7" },
  { name = "jinja2", marker = "python_version >= '3.9'", extras = ["i18n"] },
  { name = "werkzeug" },
]
[[packages.wheels]]
name = "flask-3.1.0-py3-none-any.whl"
url = "https://files.invalid/flask-3.1.0-py3-none-any.whl"
hashes = { sha256 = "1234" }
""",
        )
    )
    cases.append(
        (
            "17_unknown_keys_ignored",
            LOCK_PREFIX
            + """
[tool.moon-pyversion]
note = "this table is a reader's to ignore"

[[packages]]
name = "attrs"
version = "25.1.0"
[tool.other]
anything = [1, 2, 3]
[[packages.wheels]]
name = "attrs-25.1.0-py3-none-any.whl"
url = "https://files.invalid/attrs-25.1.0-py3-none-any.whl"
hashes = { sha256 = "abcd" }
unknown-member = "ignored"
""",
        )
    )
    cases.append(
        (
            "18_file_members",
            LOCK_PREFIX
            + """
[[packages]]
name = "spam"
version = "1.0"
[[packages.wheels]]
kind = "mutable"
name = "spam-1.0-py3-none-any.whl"
upload-time = 2024-03-01T09:15:00Z
size = 0
hashes = { sha256 = "0e00" }
[[packages.wheels]]
path = "wheelhouse/spam-1.0-2-py3-none-any.whl"
hashes = { sha256 = "1e00", blake2b_256 = "2e00" }
""",
        )
    )
    cases.append(
        (
            "19_names_are_normalized_on_comparison",
            LOCK_PREFIX
            + """
[[packages]]
name = "Zope.Interface"
version = "6.0"
dependencies = [{ name = "setuptools" }]
[[packages.wheels]]
name = "zope_interface-6.0-cp311-cp311-linux_x86_64.whl"
url = "https://files.invalid/zope_interface-6.0-cp311-cp311-linux_x86_64.whl"
hashes = { sha256 = "3e00" }
""",
        )
    )
    cases.append(
        (
            "23_vcs_with_both_url_and_path",
            LOCK_PREFIX
            + """
[[packages]]
name = "spam"
[packages.vcs]
type = "git"
url = "https://example.invalid/spam.git"
path = "../spam"
commit-id = "abc"
""",
        )
    )
    cases.append(
        (
            "22_unnormalized_spellings_are_accepted",
            LOCK_PREFIX
            + """
extras = ["Docs_Build"]
dependency-groups = ["Static_Typing"]
default-groups = ["Static_Typing"]

[[packages]]
name = "spam"
version = "1.0"
dependencies = [{ name = "attrs", extras = ["Dev_Extras"] }]
[[packages.wheels]]
name = "spam-1.0-py3-none-any.whl"
url = "https://example.invalid/spam-1.0-py3-none-any.whl"
hashes = { sha256 = "6e00" }
""",
        )
    )
    cases.append(
        (
            "21_file_record_with_a_name_but_no_location",
            LOCK_PREFIX
            + """
[[packages]]
name = "spam"
version = "1.0"
[[packages.wheels]]
name = "spam-1.0-py3-none-any.whl"
hashes = { sha256 = "5e00" }
""",
        )
    )
    cases.append(
        (
            "20_attestation_identities_are_ignored",
            LOCK_PREFIX
            + """
[[packages]]
name = "attrs"
version = "25.1.0"
[[packages.wheels]]
name = "attrs-25.1.0-py3-none-any.whl"
url = "https://files.invalid/attrs-25.1.0-py3-none-any.whl"
hashes = { sha256 = "4e00" }
[[packages.attestation-identities]]
environment = "release-pypi"
kind = "GitHub"
repository = "python-attrs/attrs"
workflow = "pypi-package.yml"
""",
        )
    )
    return cases


def curated_rejected() -> list[tuple[str, str]]:
    """Documents the specification rejects, as `(case name, document)`.

    Note what is *not* here: two entries for one name with different markers is
    the normal shape of a lock file written for several platforms, and the
    specification's install algorithm -- which narrows the applicable entries down
    and complains if two remain -- is deliberately not implemented by this library
    (its own module doc says so). So there is no rule for it here either; a
    document with two entries for one name is checked for well-formedness only.
    """
    entries: list[tuple[str, str]] = []

    def add(name: str, body: str, prefix: str = LOCK_PREFIX) -> None:
        entries.append((name, prefix + body))

    add("90_lock_version_missing", "\npackages = []\n", prefix="")
    add("91_lock_version_type", "lock-version = 1.0\ncreated-by = \"x\"\npackages = []\n", prefix="")
    add(
        "92_lock_version_not_major_minor",
        "lock-version = \"1\"\ncreated-by = \"x\"\npackages = []\n",
        prefix="",
    )
    add("93_environments_not_array", "environments = \"sys_platform == 'linux'\"\npackages = []\n")
    add("94_environments_entry_type", "environments = [1]\npackages = []\n")
    add("95_environment_marker_invalid", "environments = [\"sys_platform == linux\"]\npackages = []\n")
    add("96_requires_python_invalid", "requires-python = \">=3.9,<\"\npackages = []\n")
    add("97_requires_python_type", "requires-python = 39\npackages = []\n")
    add("98_extras_not_array", "extras = \"docs\"\npackages = []\n")
    add("9A_extra_invalid", "extras = [\"docs build\"]\npackages = []\n")
    add("9B_dependency_groups_not_array", "dependency-groups = 1\npackages = []\n")
    add("9C_dependency_groups_entry_type", "dependency-groups = [1]\npackages = []\n")
    add("9D_default_groups_invalid", "default-groups = [\"lint group\"]\npackages = []\n")
    add("9E_created_by_type", "created-by = 12\npackages = []\n", prefix='lock-version = "1.0"\n')
    add("9F_packages_missing", "", prefix=LOCK_PREFIX + "\n# no packages member at all\n")
    add("A0_packages_not_array", "packages = 1\n")
    add("A1_package_not_table", "packages = [\"attrs\"]\n")
    add("A2_package_name_missing", "\n[[packages]]\nversion = \"1.0\"\npath = \"x\"\n")
    add("A3_package_name_type", "\n[[packages]]\nname = 1\nversion = \"1.0\"\npath = \"x\"\n")
    add("A4_package_name_invalid", "\n[[packages]]\nname = \"attrs-\"\nversion = \"1.0\"\npath = \"x\"\n")
    # `"1.0.0.0.0-dev"` would *not* do here: `-dev` with no number is a legal
    # implicit `dev0`, and `packaging` accepts it. The string below is not a
    # version under any reading.
    add("A6_package_version_invalid", "\n[[packages]]\nname = \"attrs\"\nversion = \"not a version!\"\npath = \"x\"\n")
    add("A7_package_marker_invalid", "\n[[packages]]\nname = \"attrs\"\nversion = \"1.0\"\npath = \"x\"\nmarker = \"python_version >=\"\n")
    add("A8_package_requires_python_invalid", "\n[[packages]]\nname = \"attrs\"\nversion = \"1.0\"\npath = \"x\"\nrequires-python = \"3.9\"\n")
    add("A9_source_conflict_vcs_and_directory", "\n[[packages]]\nname = \"spam\"\nversion = \"1.0\"\npath = \"x\"\n[packages.vcs]\ntype = \"git\"\nurl = \"https://example.invalid/spam.git\"\ncommit-id = \"abc\"\n")
    add("B1_vcs_type_missing", "\n[[packages]]\nname = \"spam\"\n[packages.vcs]\nurl = \"https://example.invalid/spam.git\"\ncommit-id = \"abc\"\n")
    add("B2_vcs_type_invalid", "\n[[packages]]\nname = \"spam\"\n[packages.vcs]\ntype = \"github\"\nurl = \"https://example.invalid/spam.git\"\ncommit-id = \"abc\"\n")
    add("B4_vcs_commit_missing", "\n[[packages]]\nname = \"spam\"\n[packages.vcs]\ntype = \"git\"\nurl = \"https://example.invalid/spam.git\"\n")
    add("B5_directory_path_missing", "\n[[packages]]\nname = \"spam\"\n[packages.directory]\neditable = true\n")
    add("B6_archive_hashes_empty", "\n[[packages]]\nname = \"spam\"\nversion = \"1.0\"\n[packages.archive]\nurl = \"https://example.invalid/spam-1.0.tar.gz\"\nhashes = {}\n")
    add("B7_sdist_hashes_empty", "\n[[packages]]\nname = \"spam\"\nversion = \"1.0\"\n[packages.sdist]\nname = \"spam-1.0.tar.gz\"\nurl = \"https://example.invalid/spam-1.0.tar.gz\"\nhashes = {}\n")
    add("B8_wheel_not_table", "\n[[packages]]\nname = \"spam\"\nversion = \"1.0\"\nwheels = [\"spam-1.0-py3-none-any.whl\"]\n")
    add("B9_wheel_has_no_name_url_or_path", "\n[[packages]]\nname = \"spam\"\nversion = \"1.0\"\n[[packages.wheels]]\nhashes = { sha256 = \"aa\" }\n")
    add("C0_dependencies_not_array", "\n[[packages]]\nname = \"spam\"\nversion = \"1.0\"\npath = \"x\"\ndependencies = \"attrs\"\n")
    add("C1_dependency_not_table", "\n[[packages]]\nname = \"spam\"\nversion = \"1.0\"\npath = \"x\"\ndependencies = [\"attrs\"]\n")
    add("C2_dependency_name_missing", "\n[[packages]]\nname = \"spam\"\nversion = \"1.0\"\npath = \"x\"\ndependencies = [{ version = \"1.0\" }]\n")
    add("C3_dependency_version_invalid", "\n[[packages]]\nname = \"spam\"\nversion = \"1.0\"\npath = \"x\"\ndependencies = [{ name = \"attrs\", version = \"not a version\" }]\n")
    add("C4_dependency_marker_invalid", "\n[[packages]]\nname = \"spam\"\nversion = \"1.0\"\npath = \"x\"\ndependencies = [{ name = \"attrs\", marker = \"python_version\" }]\n")
    add("C5_dependency_extra_invalid_name", "\n[[packages]]\nname = \"spam\"\nversion = \"1.0\"\npath = \"x\"\ndependencies = [{ name = \"attrs\", extras = [\"docs build\"] }]\n")
    add("C6_dependency_self_reference", "\n[[packages]]\nname = \"spam\"\nversion = \"1.0\"\npath = \"x\"\ndependencies = [{ name = \"Spam\" }]\n")
    add("C8_upload_time_type", "\n[[packages]]\nname = \"spam\"\nversion = \"1.0\"\n[[packages.wheels]]\nname = \"spam-1.0-py3-none-any.whl\"\nurl = \"https://example.invalid/spam-1.0-py3-none-any.whl\"\nhashes = { sha256 = \"aa\" }\nupload-time = \"2024-03-01\"\n")
    add("C9_size_negative", "\n[[packages]]\nname = \"spam\"\nversion = \"1.0\"\n[[packages.wheels]]\nname = \"spam-1.0-py3-none-any.whl\"\nurl = \"https://example.invalid/spam-1.0-py3-none-any.whl\"\nhashes = { sha256 = \"aa\" }\nsize = -1\n")
    add("CA_not_toml", "", prefix="this is not a TOML document at all\n")
    return entries


# The divergences the library documents in `pylock.mbt`, each as a document whose
# verdict the two sides disagree about. `True` means the *reference* accepts it.
def divergences() -> list[tuple[str, str, bool]]:
    return [
        (
            "D1_created_by_missing",
            'lock-version = "1.0"\npackages = []\n',
            False,
        ),
        (
            "D2_created_by_empty",
            'lock-version = "1.0"\ncreated-by = ""\npackages = []\n',
            False,
        ),
        (
            "D3_redundant_version_next_to_a_source_tree",
            LOCK_PREFIX
            + """
[[packages]]
name = "spam"
version = "1.0"
[packages.vcs]
type = "git"
url = "https://example.invalid/spam.git"
commit-id = "abc"
""",
            False,
        ),
        (
            "D4_file_record_without_hashes",
            LOCK_PREFIX
            + """
[[packages]]
name = "spam"
version = "1.0"
[[packages.wheels]]
name = "spam-1.0-py3-none-any.whl"
url = "https://example.invalid/spam-1.0-py3-none-any.whl"
""",
            False,
        ),
        (
            "D5_upload_time_not_utc",
            LOCK_PREFIX
            + """
[[packages]]
name = "spam"
version = "1.0"
[[packages.wheels]]
name = "spam-1.0-py3-none-any.whl"
url = "https://example.invalid/spam-1.0-py3-none-any.whl"
upload-time = 2025-01-25T11:30:10+02:00
hashes = { sha256 = "aa" }
""",
            False,
        ),
        (
            "D7_version_omitted_on_a_file_list_entry",
            LOCK_PREFIX
            + """
[[packages]]
name = "spam"
[[packages.wheels]]
name = "spam-1.0-py3-none-any.whl"
url = "https://example.invalid/spam-1.0-py3-none-any.whl"
hashes = { sha256 = "aa" }
""",
            True,
        ),
        (
            "D6_lock_version_minor_not_implemented",
            'lock-version = "1.1"\ncreated-by = "mousebender"\npackages = []\n',
            True,
        ),
    ]


# --- derived from the real index responses -----------------------------------


def real_index_documents() -> list[tuple[str, dict]]:
    """The real PEP 691 responses embedded in `fixtures/index_corpus.mbt`.

    The literals are the ones `fetch_index_corpus.py` wrote, so JSON's escaping
    decodes them exactly.
    """
    if not INDEX_FIXTURE.exists():
        return []
    source = INDEX_FIXTURE.read_text(encoding="utf-8")
    start = source.index("pub let index_pypi_cases")
    chunk = source[start:]
    out = []
    for literal in re.findall(r'"(\{.*?\})"', chunk):
        try:
            document = json.loads(json.loads('"' + literal + '"'))
        except (json.JSONDecodeError, ValueError):
            continue
        out.append(document)
    return out


def derived_document(name: str, response: dict) -> str | None:
    """One lock file for `name`, from the file records of a real response."""
    files = [
        entry
        for entry in response.get("files", [])
        if isinstance(entry, dict) and entry.get("filename") and entry.get("url")
    ]
    if not files:
        return None
    by_version: dict[str, list[dict]] = {}
    for entry in files:
        version = None
        stem = entry["filename"]
        for suffix in (".whl", ".tar.gz", ".zip"):
            if stem.endswith(suffix):
                stem = stem[: -len(suffix)]
                break
        parts = stem.split("-")
        for index in range(1, len(parts)):
            candidate = "-".join(parts[index:])
            try:
                version = str(Version(candidate))
                break
            except InvalidVersion:
                continue
        if version is None:
            continue
        by_version.setdefault(version, []).append(entry)
    if not by_version:
        return None
    versions = sorted(by_version, key=Version)[-MAX_DERIVED_VERSIONS:]
    lines = [
        'lock-version = "1.0"',
        'created-by = "tools/fetch_pylock_corpus.py from a real index response"',
        "",
    ]
    for version in versions:
        entries = by_version[version][:MAX_DERIVED_FILES]
        wheels = [entry for entry in entries if entry["filename"].endswith(".whl")]
        sdists = [entry for entry in entries if not entry["filename"].endswith(".whl")]
        lines.append("[[packages]]")
        lines.append("name = %s" % json.dumps(name))
        lines.append("version = %s" % json.dumps(version))
        if sdists:
            record = sdists[0]
            lines.append("[packages.sdist]")
            lines.append("name = %s" % json.dumps(record["filename"]))
            lines.append("url = %s" % json.dumps(record["url"]))
            if record.get("size") is not None:
                lines.append("size = %d" % record["size"])
            # `upload-time` belongs to the sdist record, so it has to be written
            # *before* the `[packages.sdist.hashes]` header: a key after that
            # header belongs to the hashes table, and the reader would rightly
            # look for the stamp there and not find it.
            if record.get("upload-time"):
                lines.append(
                    "upload-time = %s" % record["upload-time"].replace("Z", "+00:00")
                )
            digest = (record.get("hashes") or {}).get("sha256")
            if digest:
                lines.append("[packages.sdist.hashes]")
                lines.append("sha256 = %s" % json.dumps(digest))
        for record in wheels:
            lines.append("[[packages.wheels]]")
            lines.append("name = %s" % json.dumps(record["filename"]))
            lines.append("url = %s" % json.dumps(record["url"]))
            if record.get("size") is not None:
                lines.append("size = %d" % record["size"])
            digest = (record.get("hashes") or {}).get("sha256")
            if digest:
                lines.append("hashes = { sha256 = %s }" % json.dumps(digest))
            if record.get("upload-time"):
                lines.append(
                    "upload-time = %s" % record["upload-time"].replace("Z", "+00:00")
                )
        lines.append("")
    return "\n".join(lines)


# --- mutations ---------------------------------------------------------------


def mutations(accepted: list[tuple[str, str]]) -> list[tuple[str, str]]:
    """Single-edit variants of the accepted documents the reference rejects."""
    out: list[tuple[str, str]] = []
    for name, document in accepted:
        candidates = [
            # `created-by` is deliberately absent-tolerant (a declared divergence),
            # and a version next to a source tree is deliberately accepted, so
            # neither rule may be mutated into a "rejection": a document that
            # breaks one of them proves nothing about agreement.
            (name + ":lock-version-dropped", document.replace('lock-version = "1.0"\n', "")),
            (
                name + ":name-gets-a-trailing-dash",
                document.replace('name = "attrs"', 'name = "attrs-"', 1),
            ),
            (
                name + ":name-is-not-a-string",
                document.replace('name = "attrs"', "name = 1", 1),
            ),
            (
                name + ":marker-loses-its-operand",
                document.replace(
                    'marker = "sys_platform == \'win32\'"',
                    'marker = "sys_platform == "',
                    1,
                ),
            ),
            (
                name + ":hashes-loses-its-entry",
                document.replace('hashes = { sha256 = "', "hashes = { unused = \"", 1),
            ),
        ]
        for candidate_name, text in candidates:
            if text == document:
                continue
            accepted_flag, _reason, _projection = reference_pylock(text)
            if not accepted_flag:
                out.append((candidate_name.replace(":", "_"), text))
    return out


# --- the PEP's own example ---------------------------------------------------

PEP751_EXAMPLE = """\
lock-version = '1.0'
environments = ["sys_platform == 'win32'", "sys_platform == 'linux'"]
requires-python = '==3.12'
created-by = 'mousebender'

[[packages]]
name = 'attrs'
version = '25.1.0'
requires-python = '>=3.8'
wheels = [
{name = 'attrs-25.1.0-py3-none-any.whl', upload-time = 2025-01-25T11:30:10.164985+00:00, url = 'https://files.pythonhosted.org/packages/fc/30/d4986a882011f9df997a55e6becd864812ccfcd821d64aac8570ee39f719/attrs-25.1.0-py3-none-any.whl', size = 63152, hashes = {sha256 = 'c75a69e28a550a7e93789579c22aa26b0f5b83b75dc4e08fe092980051e1090a'}},
]
[[packages.attestation-identities]]
environment = 'release-pypi'
kind = 'GitHub'
repository = 'python-attrs/attrs'
workflow = 'pypi-package.yml'

[[packages]]
name = 'numpy'
version = '2.2.3'
requires-python = '>=3.10'
wheels = [
{name = 'numpy-2.2.3-cp313-cp313-manylinux_2_17_x86_64.manylinux2014_x86_64.whl', url = 'https://files.pythonhosted.org/packages/0c/7e/1e5d1e5e3b9a1b3a/example.whl', size = 20000000, hashes = {sha256 = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'}},
]

[tool.moon-pyversion]
nothing = true
"""


def format_with_moon(path: Path) -> str | None:
    """Run `moon fmt` on `path` in place and return the result.

    `None` means the formatter could not be run, which is reported rather than
    treated as a pass: a fixture check that cannot run must not look like one that
    succeeded.
    """
    moon = shutil.which("moon")
    if moon is None:
        print("`moon` is not on PATH, so the formatted fixture cannot be checked")
        return None
    result = subprocess.run(
        [moon, "fmt", str(path)], capture_output=True, text=True, check=False
    )
    if result.returncode != 0:
        print(f"moon fmt failed on {path}:\n{result.stdout}{result.stderr}")
        return None
    return path.read_text(encoding="utf-8")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="recompute and compare with the committed fixture instead of writing it",
    )
    args = parser.parse_args(argv)

    accepted = curated()
    rejected = curated_rejected()
    declared = divergences()
    mutated = mutations(accepted)

    derived: list[tuple[str, str, str]] = []
    skipped = []
    for response in real_index_documents():
        name = response.get("name")
        if not name:
            skipped.append("<response without a name>")
            continue
        document = derived_document(name, response)
        if document is None:
            skipped.append(name)
            continue
        ok, reason, projected = reference_pylock(document)
        if not ok:
            sys.exit(f"the derived document for {name} is rejected: {reason}")
        derived.append((name, document, projected or ""))

    # Every accepted case must be accepted by the reference, or it belongs in the
    # rejected list (or in the declared divergences).
    cases = []
    for name, document in accepted:
        ok, reason, projected = reference_pylock(document)
        if not ok:
            sys.exit(f"curated case {name} is rejected by the reference: {reason}")
        if projected is None:
            sys.exit(f"curated case {name} has no projection")
        cases.append((name, document, projected))
    for name, document, expected in declared:
        ok, reason, _projection = reference_pylock(document)
        if ok != expected:
            sys.exit(
                f"declared divergence {name} says the reference "
                f"{'accepts' if expected else 'rejects'} it, but it "
                f"{'accepts' if ok else 'rejects'} it ({reason})"
            )
        if text_has_separators(document):
            sys.exit(f"{name} contains a value the projection cannot separate")
    for name, document in rejected + mutated:
        ok, reason, _projection = reference_pylock(document)
        if ok:
            sys.exit(f"rejected case {name} is accepted by the reference")

    CASES.mkdir(exist_ok=True)
    for path in sorted(CASES.glob("*.toml")):
        path.unlink()
    for name, document in accepted:
        (CASES / (name + ".toml")).write_text(document, encoding="utf-8")
    for name, document in rejected + mutated:
        (CASES / (name + ".toml")).write_text(document, encoding="utf-8")
    for name, document, _expected in declared:
        (CASES / (name + ".toml")).write_text(document, encoding="utf-8")
    (CASES / "divergences.txt").write_text(render_divergences(declared), encoding="utf-8")

    lines = [HEADER]
    lines.append("///|")
    lines.append("/// The environment every `pylock` record decides applicability in, as the")
    lines.append("/// single-valued keys. `extra` is PEP 508's own key; the two set-valued keys")
    lines.append("/// PEP 751 adds to the marker vocabulary are declared below.")
    lines.append("pub let pylock_environment : Array[(String, String)] = [")
    for key, value in ENVIRONMENT:
        lines.append("  (%s, %s)," % (mbt_string(key), mbt_string(value)))
    lines.append("]")
    lines.append("")
    lines.append("///|")
    lines.append("/// The set-valued half of the same environment. Both are empty: no extra and")
    lines.append("/// no dependency group is requested, so a marker testing one is answered")
    lines.append("/// `false` rather than being left unanswered.")
    lines.append("pub let pylock_environment_sets : Array[(String, Array[String])] = [")
    for key, values in ENVIRONMENT_SETS:
        rendered = ", ".join(mbt_string(item) for item in values)
        lines.append("  (%s, [%s])," % (mbt_string(key), rendered))
    lines.append("]")
    lines.append("")
    lines.append(comment(
        "Curated `pylock.toml` documents the specification accepts, as\n"
        "`(case name, document, projection)`. The projection is the mapping\n"
        "written down once in `tools/fetch_pylock_corpus.py`, re-derived there\n"
        "from the TOML, and the `pylock` records the emitter writes are\n"
        "compared against it. The PEP's own example is parsed verbatim.\n"
        "\n"
        "Regenerate with tools/fetch_pylock_corpus.py; do not edit by hand."
    ))
    lines.append("pub let pylock_cases : Array[(String, String, String)] = [")
    for name, document, projected in cases:
        lines.append("  (%s, %s, %s)," % (mbt_string(name), mbt_string(document), mbt_string(projected)))
    lines.append("]")
    lines.append("")
    lines.append(comment(
        "Documents the specification rejects, as `(case name, document)`: one per\n"
        "rule, plus single-edit mutations of the accepted documents. Their codes are\n"
        "not stored: PEP 751 has no schema, so the library names the rules in its own\n"
        "vocabulary and the harness only agrees that something was rejected."
    ))
    lines.append("pub let pylock_bad_cases : Array[(String, String)] = [")
    for name, document in rejected + mutated:
        lines.append("  (%s, %s)," % (mbt_string(name), mbt_string(document)))
    lines.append("]")
    lines.append("")
    lines.append(comment(
        "Lock files derived from the %d real PEP 691 index responses in\n"
        "`index_corpus.mbt`: one per project, as `(project, document, projection)`.\n"
        "The *documents* are constructed by tools/fetch_pylock_corpus.py, and the\n"
        "file records inside them -- name, URL, sha256, size, upload time -- are the\n"
        "index response's own. The index spells the UTC suffix `Z`; the document\n"
        "writes the same instant as `+00:00`, because that is the spelling the\n"
        "reference reader can reproduce from its `datetime`, and the instant is\n"
        "unchanged. At most %d versions and %d file records are taken from each\n"
        "response, so the corpus stays a corpus." % (
            len(derived),
            MAX_DERIVED_VERSIONS,
            MAX_DERIVED_FILES,
        )
    ))
    lines.append("pub let pylock_pypi_cases : Array[(String, String, String)] = [")
    for name, document, projected in derived:
        lines.append("  (%s, %s, %s)," % (mbt_string(name), mbt_string(document), mbt_string(projected)))
    lines.append("]")
    lines.append("")
    lines.append(comment(
        "The documents where this library deliberately answers differently from the\n"
        "specification, as `(case name, does the reference accept it)`. Divergence is\n"
        "the point of the record: the harness asserts that the two answers really do\n"
        "differ, and that the reference answers the way this table says.\n"
        "`pylock_cases/divergences.txt` explains each one."
    ))
    lines.append("pub let pylock_divergences : Array[(String, Bool)] = [")
    for name, _document, expected in declared:
        lines.append("  (%s, %s)," % (mbt_string(name), "true" if expected else "false"))
    lines.append("]")
    lines.append("")
    lines.append(comment(
        "The documents behind `pylock_divergences`, as `(case name, document)`. They\n"
        "are emitted as ordinary `pylock` records; the declaration above only says\n"
        "which direction the difference goes."
    ))
    lines.append("pub let pylock_divergence_cases : Array[(String, String)] = [")
    for name, document, _expected in declared:
        lines.append("  (%s, %s)," % (mbt_string(name), mbt_string(document)))
    lines.append("]")
    fixture = "\n".join(lines) + "\n"

    JSON_OUT.write_text(
        json.dumps(
            {
                "generated_by": "tools/fetch_pylock_corpus.py",
                "reference": (
                    "PEP 751 read a second time in reference_pylock, plus "
                    "packaging.markers for marker syntax/evaluation and "
                    "packaging.version/specifiers for versions; there is no "
                    "external pylock.toml implementation to compare against."
                ),
                "curated_accepted": [name for name, _document in accepted],
                "curated_rejected": [name for name, _document in rejected],
                "mutated_rejected": [name for name, _document in mutated],
                "divergences": [
                    {
                        "name": name,
                        "reference_accepts": expected,
                        "reason": REASONS[name],
                    }
                    for name, _document, expected in declared
                ],
                "derived": [
                    {"name": name, "bytes": len(document)} for name, document, _p in derived
                ],
                "derived_skipped": skipped,
                "max_derived_versions": MAX_DERIVED_VERSIONS,
                "max_derived_files": MAX_DERIVED_FILES,
                "environment": {
                    "single": dict(ENVIRONMENT),
                    "sets": {key: values for key, values in ENVIRONMENT_SETS},
                },
            },
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )

    if args.check:
        # The comparison has to be made *after* `moon fmt`, because the fixture is
        # a formatted MoonBit file and this generator emits compact text. Comparing
        # the raw generation would fail on layout alone -- which is exactly how a
        # stale fixture slipped through once, when the committed file was the
        # hand-written stub rather than any generation at all.
        before = MBT.read_text(encoding="utf-8") if MBT.exists() else ""
        MBT.write_text(fixture, encoding="utf-8")
        formatted = format_with_moon(MBT)
        if formatted is None:
            return 2
        MBT.write_text(before, encoding="utf-8")
        if before != formatted:
            print(f"{MBT} is not what tools/fetch_pylock_corpus.py generates")
            print("regenerate it, then run `moon fmt` on it and commit both")
            return 1
        print(f"{MBT} is up to date")
        return 0

    MBT.write_text(fixture, encoding="utf-8")
    print(
        "%d accepted + %d rejected + %d mutated + %d divergent curated, "
        "%d derived from real index responses -> %s"
        % (
            len(accepted),
            len(rejected),
            len(mutated),
            len(declared),
            len(derived),
            MBT.name,
        )
    )
    return 0


HEADER = """///|
/// Generated by tools/fetch_pylock_corpus.py; do not edit by hand.
///
/// The documents here are the differential corpus's PEP 751 inputs: curated
/// `pylock.toml` documents written from the specification, documents derived from
/// the real index responses in `index_corpus.mbt`, and the declared divergences.
/// The verdicts and the projections are the second reading of PEP 751 that lives
/// in tools/fetch_pylock_corpus.py -- there is no external pylock.toml reader to
/// compare against, and saying so is part of the record."""

# Why each declared divergence goes the way it does. Kept here so the fixture and
# `pylock_cases/divergences.txt` cannot tell different stories.
REASONS = {
    "D1_created_by_missing": (
        "PEP 751 requires `created-by`; this reader treats it as optional, because a "
        "lock file without it is still a usable lock file and the field is provenance."
    ),
    "D2_created_by_empty": (
        "An empty string counts as an absent value here, the rule `metadata.mbt` "
        "applies to an empty header value; PEP 751 would reject it."
    ),
    "D3_redundant_version_next_to_a_source_tree": (
        "The specification says a source tree MUST NOT record `version`; this reader "
        "keeps it, because a version key is what a resolved set is checked against and "
        "the MUST NOT is a locker-side rule."
    ),
    "D4_file_record_without_hashes": (
        "`hashes` is required on `wheels`, `sdist` and `archive`; this reader accepts a "
        "record without it -- the digest is then simply unknown -- but still rejects an "
        "empty `hashes` table, which the specification forbids outright."
    ),
    "D5_upload_time_not_utc": (
        "`upload-time` must be recorded in UTC; this reader only checks that it is a "
        "TOML datetime and records the spelling verbatim, because no date arithmetic "
        "happens anywhere in the library."
    ),
    "D7_version_omitted_on_a_file_list_entry": (
        "`packages.version` is only a SHOULD for an entry that names files; this "
        "reader requires it unless the entry is a direct reference, because the "
        "version key is what a resolved set is checked against."
    ),
    "D6_lock_version_minor_not_implemented": (
        "The specification tells a reader that supports the major version but not the "
        "minor one to warn; there is no warning channel here, so `1.1` is rejected "
        "instead of being silently accepted."
    ),
}


def comment(text: str) -> str:
    """A `///|` doc comment block."""
    lines = ["///|"]
    for line in text.split("\n"):
        lines.append(("/// " + line).rstrip())
    return "\n".join(lines)


def render_divergences(declared: list[tuple[str, str, bool]]) -> str:
    out = [
        "Declared divergences between this library and PEP 751.",
        "",
        "Each line names a document in this directory, which side accepts it, and",
        "why. The corpus asserts the difference in both directions: a divergence that",
        "stops being one fails the differential run, and a difference that is not",
        "declared here is reported as a mismatch.",
        "",
    ]
    for name, _document, expected in declared:
        out.append("%s: reference %s, library %s" % (
            name,
            "accepts" if expected else "rejects",
            "rejects" if expected else "accepts",
        ))
        out.append("    " + REASONS[name])
        out.append("")
    return "\n".join(out)


def text_has_separators(document: str) -> bool:
    """True when a value would collide with the projection's separators.

    The projection separates fields with `;`, groups with `|` and list items with
    `^`, and it does not escape the values, so a document whose markers, names or
    URLs contain one of those characters could not be compared. None of the
    documents here does; this is asserted rather than hoped for.
    """
    for line in document.split("\n"):
        if line.count('"') >= 2 or line.count("'") >= 2:
            if any(char in line for char in (";", "^")):
                return True
    return False


if __name__ == "__main__":
    raise SystemExit(main())
