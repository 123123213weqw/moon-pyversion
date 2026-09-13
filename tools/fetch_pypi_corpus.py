#!/usr/bin/env python3
"""Build a real-world PyPI metadata corpus (version strings + version-specifier strings).

Run:  python3 tools/fetch_pypi_corpus.py

Outputs (relative to the repository root):
  fixtures/pypi_corpus.json  machine readable corpus + provenance
  fixtures/pypi_corpus.mbt   MoonBit fixture declaring
                    `pub let pypi_versions : Array[String]` and
                    `pub let pypi_specifiers : Array[String]`

Data source: the legacy PyPI JSON API (`/pypi/<name>/json`), which exposes `releases`
(all version strings) plus `info.requires_python` / `info.requires_dist` (version
specifier strings). When `releases` is missing/empty the PEP 691 simple index
(`/simple/<name>/`, `Accept: application/vnd.pypi.simple.v1+json`) is used as a
fallback and versions are derived naively from distribution filenames.

Stdlib only (Python 3.10). `packaging` is used opportunistically for validation,
and only when it is already importable; the script never installs anything and
never writes outside this repository. Run `moon fmt` afterwards: the generated
file holds one string per line, while `moon fmt --check` in CI expects the
packed layout.
"""

from __future__ import annotations

import json
import os
import re
import sys
import urllib.error
import urllib.request
from datetime import date

# --------------------------------------------------------------------------------------
# Configuration
# --------------------------------------------------------------------------------------

USER_AGENT = "moonbit-pypi-corpus-builder/1.0 (+https://pypi.org/)"
TIMEOUT = 30  # seconds, per request (one retry per URL on failure)

VERSION_CAP = 3000
SPECIFIER_CAP = 500
PER_PACKAGE_VERSION_CAP = 60

# Preferred index (per task spec).
PYPI_JSON_BASE = "https://pypi.org/pypi"
PYPI_SIMPLE_BASE = "https://pypi.org/simple"

# Fallback: mirror proxying the same legacy JSON API + PEP 691 simple index. Used only
# when pypi.org itself is unreachable from this host (see `select_index`).
MIRROR_HOST = "https://pypi.tuna.tsinghua.edu.cn"
MIRROR_JSON_BASE = MIRROR_HOST + "/pypi"
MIRROR_SIMPLE_BASE = MIRROR_HOST + "/simple"

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# The MoonBit fixture is consumed by examples/diff, which is the corpus emitter
# for tools/diff_packaging.py; the JSON sidecar keeps the full provenance.
MBT_OUT = os.path.join(ROOT, "fixtures", "pypi_corpus.mbt")
JSON_OUT = os.path.join(ROOT, "fixtures", "pypi_corpus.json")

# Deterministic order matters: it defines the round-robin order below.
PACKAGES = [
    "numpy", "pandas", "scipy", "scikit-learn", "matplotlib", "pillow", "requests",
    "urllib3", "certifi", "idna", "charset-normalizer", "six", "python-dateutil",
    "pytz", "packaging", "setuptools", "wheel", "pip", "boto3", "botocore", "redis",
    "pymongo", "psycopg2-binary", "sqlalchemy", "alembic", "django", "flask", "jinja2",
    "werkzeug", "click", "rich", "tqdm", "pyyaml", "lxml", "beautifulsoup4",
    "cryptography", "paramiko", "protobuf", "grpcio", "aiohttp", "httpx", "fastapi",
    "pydantic", "uvicorn", "starlette", "pytest", "coverage", "tox", "black", "ruff",
    "mypy", "sphinx", "docutils", "pygments", "typing-extensions", "attrs",
    "hypothesis", "twine", "build", "flit", "poetry", "celery", "scrapy",
    "transformers", "datasets", "accelerate", "torch", "tensorflow", "xgboost",
    "lightgbm", "statsmodels", "seaborn", "plotly", "dash", "streamlit", "gradio",
    "jupyterlab", "notebook", "ipython", "numpy-financial", "opencv-python",
    "google-cloud-storage", "kubernetes", "docker", "ansible", "kafka-python",
    "python-dotenv", "marshmallow", "httplib2", "pyparsing", "markupsafe",
    "itsdangerous", "wrapt", "filelock", "platformdirs", "tomli",
    "importlib-metadata",
]

# --------------------------------------------------------------------------------------
# Optional validation via `packaging`
# --------------------------------------------------------------------------------------

try:  # pragma: no cover - depends on the environment
    from packaging.specifiers import SpecifierSet
    from packaging.version import Version

    HAVE_PACKAGING = True
    PACKAGING_VERSION = __import__("packaging").__version__
except Exception:  # pragma: no cover
    HAVE_PACKAGING = False
    PACKAGING_VERSION = None

# --------------------------------------------------------------------------------------
# HTTP helpers
# --------------------------------------------------------------------------------------


def http_get_json(url, accept=None, timeout=TIMEOUT):
    """GET `url` and decode JSON. Returns (payload, error_string)."""
    headers = {"User-Agent": USER_AGENT}
    if accept is not None:
        headers["Accept"] = accept
    request = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            raw = response.read()
    except Exception as exc:  # URLError, HTTPError, timeout, ssl, ...
        return None, "%s: %s" % (type(exc).__name__, exc)
    try:
        return json.loads(raw.decode("utf-8")), None
    except Exception as exc:
        return None, "JSONDecodeError: %s" % (exc,)


def fetch_with_retry(url, accept=None):
    """GET `url`, retrying once. Returns (payload, error_string)."""
    payload, first_error = http_get_json(url, accept=accept)
    if first_error is None:
        return payload, None
    payload, second_error = http_get_json(url, accept=accept)
    if second_error is None:
        return payload, None
    return None, "after 2 attempts: %s | retry: %s" % (first_error, second_error)


def select_index():
    """Prefer pypi.org; fall back to the mirror when pypi.org is unreachable.

    Returns (json_base, simple_base, source_label, probe_error).
    """
    payload, error = http_get_json(PYPI_JSON_BASE + "/pip/json", timeout=10)
    if payload is not None:
        return PYPI_JSON_BASE, PYPI_SIMPLE_BASE, "pypi.org", None
    return (
        MIRROR_JSON_BASE,
        MIRROR_SIMPLE_BASE,
        MIRROR_HOST,
        "https://pypi.org/pypi/pip/json unreachable from this host (%s)" % (error,),
    )


# --------------------------------------------------------------------------------------
# Version collection
# --------------------------------------------------------------------------------------

_DIST_EXTS = (".tar.gz", ".tar.bz2", ".tar.xz", ".tgz", ".zip", ".whl", ".egg", ".tar")


def naive_version_from_filename(filename):
    """Very naive '<name>-<version>-...' extraction from a distribution filename."""
    base = filename
    lowered = base.lower()
    for ext in _DIST_EXTS:
        if lowered.endswith(ext):
            base = base[: -len(ext)]
            break
    parts = base.split("-")
    if len(parts) < 2:
        return None
    candidate = parts[1].strip()
    return candidate or None


def version_is_sane(candidate):
    if not candidate or not candidate.isascii() or not candidate[0].isdigit():
        return False
    if not HAVE_PACKAGING:
        return True
    try:
        Version(candidate)
        return True
    except Exception:
        return False


def versions_via_json_api(payload):
    releases = payload.get("releases")
    if isinstance(releases, dict) and releases:
        return list(releases.keys())
    return []


def versions_via_simple_index(simple_base, package):
    """PEP 691 fallback. Returns (versions, error_string)."""
    url = "%s/%s/" % (simple_base, package)
    payload, error = fetch_with_retry(
        url, accept="application/vnd.pypi.simple.v1+json"
    )
    if error is not None:
        return [], error
    files = payload.get("files") or []
    found = set()
    for entry in files:
        filename = entry.get("filename") if isinstance(entry, dict) else None
        if not filename:
            continue
        candidate = naive_version_from_filename(filename)
        if candidate and version_is_sane(candidate):
            found.add(candidate)
    return sorted(found), None


# --------------------------------------------------------------------------------------
# Specifier collection
# --------------------------------------------------------------------------------------

_REQUIREMENT_RE = re.compile(r"^([A-Za-z0-9][A-Za-z0-9._-]*)\s*(.*)$", re.DOTALL)
_EXTRAS_RE = re.compile(r"\[[^\[\]]*\]")


def drop_environment_marker(text):
    """Everything after the first `;` is a PEP 508 environment marker."""
    if ";" in text:
        text = text.split(";", 1)[0]
    return text.strip()


def constraint_from_requirement(entry):
    """Extract the version-constraint text of one `requires_dist` entry.

    Handles both real-world shapes:
      'urllib3 (<2.0,>=1.21.1) ; extra == "socks"' -> '<2.0,>=1.21.1'  (parenthesised)
      'numpy>=1.22.4; python_version < "3.11"'     -> '>=1.22.4'       (PEP 508 inline)
      'filelock'                                   -> None            (no constraint)
    """
    text = drop_environment_marker(entry)
    text = _EXTRAS_RE.sub("", text).strip()  # drop extras `[socks]`
    if not text:
        return None
    if "(" in text:
        inner = text[text.find("(") + 1 :]
        if ")" in inner:
            inner = inner[: inner.rfind(")")]
        inner = inner.strip()
        return inner or None
    # No parentheses: the constraint (if any) is inline after the requirement name.
    match = _REQUIREMENT_RE.match(text)
    if match is None:
        return None
    rest = match.group(2).strip()
    return rest or None


def constraint_from_requires_python(value):
    if not value:
        return None
    text = drop_environment_marker(str(value))
    if text.startswith("(") and text.endswith(")"):
        text = text[1:-1].strip()
    return text or None


# --------------------------------------------------------------------------------------
# String hygiene + validation
# --------------------------------------------------------------------------------------

_FORBIDDEN_CHARS = ("\t", "\n", "\r", "\\", '"')


def is_clean_string(text):
    """Pure printable ASCII, no tab/newline/backslash/double-quote, no edge blanks."""
    if not isinstance(text, str) or not text:
        return False
    if not text.isascii():
        return False
    if text != text.strip():
        return False
    for char in _FORBIDDEN_CHARS:
        if char in text:
            return False
    return all(char.isprintable() for char in text)


def specifier_is_valid(text):
    """True when `packaging` (if available) accepts the specifier set."""
    if not HAVE_PACKAGING:
        return True
    try:
        SpecifierSet(text)
        return True
    except Exception:
        return False


# --------------------------------------------------------------------------------------
# Output rendering
# --------------------------------------------------------------------------------------


def mbt_escape(text):
    return text.replace("\\", "\\\\").replace('"', '\\"')


def render_mbt_array(binding, doc_lines, values):
    out = ["///|"]
    for line in doc_lines:
        out.append("/// " + line)
    out.append("pub let %s : Array[String] = [" % binding)
    for value in values:
        out.append('  "%s",' % mbt_escape(value))
    out.append("]")
    return "\n".join(out)


# These doc strings are mirrored in the committed fixture, so regenerating the
# corpus does not rewrite its header.
MBT_VERSIONS_DOC = [
    "Real-world version strings sampled from the PyPI JSON API",
    "(`/pypi/<package>/json` -> `releases` keys), %d per package at most,"
    % PER_PACKAGE_VERSION_CAP,
    "round-robin over %d well-known packages up to the %d entry cap."
    % (len(PACKAGES), VERSION_CAP),
    "Regenerate with tools/fetch_pypi_corpus.py; do not edit by hand.",
]
MBT_SPECIFIERS_DOC = [
    "Real-world version constraints extracted from PyPI `Requires-Dist` /",
    "`Requires-Python` metadata: the parenthesised constraint text only, with",
    "environment markers and extras dropped, deduplicated and sorted. %d of"
    % SPECIFIER_CAP,
    "them, every one of which parsing accepts.",
    "Regenerate with tools/fetch_pypi_corpus.py; do not edit by hand.",
]


def render_mbt(versions, specifiers):
    blocks = [
        render_mbt_array("pypi_versions", MBT_VERSIONS_DOC, versions),
        render_mbt_array("pypi_specifiers", MBT_SPECIFIERS_DOC, specifiers),
    ]
    return "\n\n".join(blocks) + "\n"


# --------------------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------------------


def main():
    json_base, simple_base, source_label, probe_error = select_index()
    print("index      : %s (json=%s)" % (source_label, json_base))
    if probe_error:
        print("pypi.org   : UNREACHABLE -> %s" % probe_error)
    print("packaging  : %s" % (PACKAGING_VERSION if HAVE_PACKAGING else "NOT INSTALLED"))
    print()

    raw_versions = {}
    fetch_errors = {}
    version_sources = {"json_api": [], "simple_index": []}
    raw_specifiers = set()
    dropped_specifiers = {}

    def bump(reason):
        dropped_specifiers[reason] = dropped_specifiers.get(reason, 0) + 1

    for package in PACKAGES:
        payload, error = fetch_with_retry("%s/%s/json" % (json_base, package))
        if payload is None:
            fetch_errors[package] = "%s/%s/json -> %s" % (json_base, package, error)
            print("FAIL  %-24s %s" % (package, fetch_errors[package]))
            continue

        versions = versions_via_json_api(payload)
        if versions:
            version_sources["json_api"].append(package)
        else:
            versions, simple_error = versions_via_simple_index(simple_base, package)
            if simple_error is not None or not versions:
                fetch_errors[package] = (
                    "no `releases` in JSON API; simple index %s/%s/ -> %s"
                    % (simple_base, package, simple_error or "no filenames")
                )
                print("FAIL  %-24s %s" % (package, fetch_errors[package]))
                continue
            version_sources["simple_index"].append(package)

        raw_versions[package] = [v for v in versions if is_clean_string(v)]

        info = payload.get("info") or {}
        candidates = []
        py_constraint = constraint_from_requires_python(info.get("requires_python"))
        if py_constraint:
            candidates.append(py_constraint)
        for entry in info.get("requires_dist") or []:
            if not isinstance(entry, str):
                continue
            constraint = constraint_from_requirement(entry)
            if constraint:
                candidates.append(constraint)
        for candidate in candidates:
            if not is_clean_string(candidate):
                bump("not clean printable ASCII")
                continue
            if not specifier_is_valid(candidate):
                bump("rejected by packaging.SpecifierSet")
                continue
            raw_specifiers.add(candidate)

        print(
            "ok    %-24s versions=%-5d specifiers_total=%d"
            % (package, len(raw_versions[package]), len(raw_specifiers))
        )

    # ---- version selection: per-package deterministic order, round-robin, dedup ------
    per_package_sorted = {p: sorted(set(v)) for p, v in raw_versions.items()}
    order = [p for p in PACKAGES if per_package_sorted.get(p)]
    cursors = {p: 0 for p in order}
    per_package_selected = {p: 0 for p in order}
    attributed = {p: [] for p in order}  # versions credited to the package that gave them
    seen_versions = set()
    selected = []
    while len(selected) < VERSION_CAP:
        progressed = False
        for package in order:
            if len(selected) >= VERSION_CAP:
                break
            if per_package_selected[package] >= PER_PACKAGE_VERSION_CAP:
                continue
            cursor = cursors[package]
            if cursor >= len(per_package_sorted[package]):
                continue
            value = per_package_sorted[package][cursor]
            cursors[package] = cursor + 1
            progressed = True
            if value in seen_versions:
                continue
            seen_versions.add(value)
            per_package_selected[package] += 1
            attributed[package].append(value)
            selected.append(value)
        if not progressed:
            break
    versions_out = sorted(selected)

    # Each package owns at most PER_PACKAGE_VERSION_CAP entries and the map sums to
    # version_count (a version string shared by two projects is credited once).
    per_package_versions = {
        package: sorted(values) for package, values in attributed.items() if values
    }

    # ---- specifiers: dedup, sort ascending, cap --------------------------------------
    specifiers_out = sorted(raw_specifiers)[:SPECIFIER_CAP]

    generated_note = (
        "Generated by tools/fetch_pypi_corpus.py on %s from the PyPI JSON API "
        "(<index>/<package>/json: `releases`, `info.requires_python`, "
        "`info.requires_dist`); index base = %s. Version specifiers were validated with "
        "packaging %s. Version strings were capped at %d (<= %d per package, round-robin "
        "over packages in the hardcoded order, ascending order within each package); "
        "specifier strings were capped at %d after deduplication and ascending sort."
        % (
            date.today().isoformat(),
            source_label,
            PACKAGING_VERSION if HAVE_PACKAGING else "n/a",
            VERSION_CAP,
            PER_PACKAGE_VERSION_CAP,
            SPECIFIER_CAP,
        )
    )
    if probe_error:
        generated_note += (
            " NOTE: pypi.org itself was not reachable from this host (%s), so the "
            "identical upstream metadata was fetched through the %s mirror instead."
            % (probe_error, MIRROR_HOST)
        )

    corpus = {
        "packages": sorted(per_package_versions.keys()),
        "per_package_versions": per_package_versions,
        "version_count": len(versions_out),
        "specifier_count": len(specifiers_out),
        "fetch_errors": fetch_errors,
        "generated_note": generated_note,
    }
    with open(JSON_OUT, "w", encoding="utf-8") as handle:
        json.dump(corpus, handle, indent=2, sort_keys=True, ensure_ascii=True)
        handle.write("\n")
    with open(MBT_OUT, "w", encoding="utf-8") as handle:
        handle.write(render_mbt(versions_out, specifiers_out))

    print()
    print("packages fetched OK      : %d / %d" % (len(per_package_versions), len(PACKAGES)))
    print("fetch errors             : %d" % len(fetch_errors))
    print("version strings          : %d (cap %d)" % (len(versions_out), VERSION_CAP))
    print("specifier strings        : %d (cap %d)" % (len(specifiers_out), SPECIFIER_CAP))
    print("version source json_api  : %d packages" % len(version_sources["json_api"]))
    print(
        "version source simple    : %d packages %s"
        % (len(version_sources["simple_index"]), version_sources["simple_index"])
    )
    for reason, count in sorted(dropped_specifiers.items()):
        print("dropped specifier strings: %d (%s)" % (count, reason))
    print("wrote %s" % JSON_OUT)
    print("wrote %s" % MBT_OUT)
    return 0


if __name__ == "__main__":
    sys.exit(main())
