"""Build the core-metadata fixture used by the differential corpus.

Two sets of documents are merged into `fixtures/metadata_corpus.mbt`:

- the curated cases under `metadata_cases/*.metadata`, which exercise the rules
  of the core metadata specification (PEP 566 as amended by 621, 639, 643, 685
  and 753) one at a time;
- real `METADATA` files served next to the wheels on PyPI, fetched through the
  PEP 658 `.metadata` sidecar (`<file url>.metadata`). These are the documents a
  tool actually has to read, so they are the evidence that the rules were not
  invented for the corpus.

Every verdict in the fixture comes from PyPA `packaging` 26.3
(`Metadata.from_email(data, validate=True)`), which is also the oracle the
differential harness replays against. `metadata_cases/divergences.txt` names the
documents where this library deliberately answers differently; each entry is
checked here against the reference implementation, so the list cannot go stale
and a divergence that stops being real is reported rather than tolerated.

Run with the pinned interpreter::

    ~/oracle-versions/venv26.3/bin/python -B tools/fetch_metadata_corpus.py

Use `--offline` to rebuild from the cached `fixtures/metadata_pypi.json` without
touching the network.
"""

from __future__ import annotations

import argparse
import json
import socket
import sys
import urllib.error
import urllib.request
from pathlib import Path

try:
    from packaging.metadata import Metadata as ReferenceMetadata
except ImportError:  # pragma: no cover - the pinned venv always has it
    sys.exit("packaging is required: run with the pinned oracle interpreter")

ROOT = Path(__file__).resolve().parents[1]
CASES = ROOT / "metadata_cases"
DIVERGENCES = CASES / "divergences.txt"
MBT = ROOT / "fixtures" / "metadata_corpus.mbt"
JSON_OUT = ROOT / "fixtures" / "metadata_corpus.json"
PYPI_JSON = ROOT / "fixtures" / "metadata_pypi.json"
PACKAGE_INDEX = ROOT / "fixtures" / "pypi_corpus.json"

# The JSON endpoint of the index we can reach. One request per project is enough:
# it lists every release with its files, and each file has a PEP 658 `.metadata`
# sidecar served from the file host. Both are read-only and public.
INDEX = "https://pypi.tuna.tsinghua.edu.cn/pypi/{name}/json"
SIDECAR = "{url}.metadata"

# A document larger than this is dropped instead of embedded: a corpus record
# carries the whole document, and one 200 kB description would weigh more than
# the rest of the corpus together. The count is reported, never hidden.
MAX_DOCUMENT = 12000
# How many versions of each package to try.
VERSIONS_PER_PACKAGE = 3


def reference_verdict(text: str) -> tuple[bool, str]:
    """What the reference implementation does with one document.

    Returns `(accepted, detail)` where `detail` is the error type and message of
    the first problem, which is what a failing record has to reproduce.
    """
    try:
        ReferenceMetadata.from_email(text, validate=True)
    except Exception as error:  # noqa: BLE001 - the type is part of the answer
        return False, f"{type(error).__name__}: {error}"
    return True, ""


def read_divergences() -> list[tuple[str, bool]]:
    """Declared divergences: `name accept|reject  # reason` per line."""
    if not DIVERGENCES.exists():
        return []
    out: list[tuple[str, bool]] = []
    for line in DIVERGENCES.read_text(encoding="utf-8").splitlines():
        line = line.split("#", 1)[0].strip()
        if not line:
            continue
        parts = line.split()
        if len(parts) != 2 or parts[1] not in ("accept", "reject"):
            sys.exit(f"divergences.txt: expected `<case> accept|reject`, got {line!r}")
        out.append((parts[0], parts[1] == "accept"))
    return out


def fetch(url: str, cache: Path) -> bytes | None:
    if cache.exists():
        return cache.read_bytes()
    request = urllib.request.Request(
        url, headers={"User-Agent": "moon-pyversion-corpus (offline metadata fixture)"}
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            payload = response.read()
    except (urllib.error.URLError, TimeoutError) as error:
        print(f"  fetch failed: {url} ({error})", file=sys.stderr)
        return None
    cache.parent.mkdir(parents=True, exist_ok=True)
    cache.write_bytes(payload)
    return payload


def real_documents(offline: bool) -> tuple[list[tuple[str, str]], dict]:
    """Real `METADATA` documents for the packages of the PyPI corpus.

    Fetched documents are cached under `fixtures/metadata_cache/` (not
    committed), so `--offline` can rebuild the fixture from what was already
    downloaded without touching the network.
    """
    cache_dir = PYPI_JSON.parent / "metadata_cache"

    if offline:
        # The cache holds every document that was ever downloaded, including the
        # ones the online run dropped for size. Rebuilding from the previous
        # provenance keeps the selection identical instead of quietly changing
        # which documents the corpus covers; without it, the cache is filtered
        # by the same rules the fetch applies.
        names: list[str] | None = None
        if JSON_OUT.exists():
            provenance = json.loads(JSON_OUT.read_text(encoding="utf-8"))
            names = [
                entry["name"]
                for entry in provenance.get("documents", [])
                if entry.get("source") == "pypi"
            ]
        paths = (
            [cache_dir / f"{name}.metadata" for name in names]
            if names is not None
            else sorted(cache_dir.glob("*.metadata"))
        )
        documents = []
        skipped = {"offline": True, "missing": 0, "larger_than_limit": 0}
        for path in paths:
            if not path.exists():
                skipped["missing"] += 1
                continue
            text = path.read_text(encoding="utf-8")
            if len(text) > MAX_DOCUMENT:
                skipped["larger_than_limit"] += 1
                continue
            documents.append((path.stem, text))
        if not documents:
            sys.exit(f"--offline needs documents under {cache_dir}")
        return documents, skipped

    # A hanging connection would stall the whole fixture, so every socket gets
    # the same bound the per-request timeouts use.
    socket.setdefaulttimeout(30)

    if not PACKAGE_INDEX.exists():
        sys.exit(f"missing {PACKAGE_INDEX}; run tools/fetch_pypi_corpus.py first")
    index = json.loads(PACKAGE_INDEX.read_text(encoding="utf-8"))
    packages = index["packages"]
    per_package = index["per_package_versions"]
    documents: list[tuple[str, str]] = []
    skipped: dict[str, int] = {"larger_than_limit": 0, "no_wheel": 0, "unavailable": 0}
    fetch_errors: list[str] = []

    for package in packages:
        payload = fetch(INDEX.format(name=package), cache_dir / f"{package}.json")
        if payload is None:
            skipped["unavailable"] += 1
            fetch_errors.append(package)
            continue
        try:
            info = json.loads(payload)
        except json.JSONDecodeError:
            skipped["unavailable"] += 1
            fetch_errors.append(package)
            continue
        releases = info.get("releases") or {}
        versions = [v for v in per_package.get(package, []) if v in releases]
        # Final releases first: they are the ones a tool is most likely to read,
        # and their metadata is the most complete.
        ordered = [v for v in versions if not any(ch in v for ch in "ab")] + versions
        taken = 0
        for version in ordered:
            if taken >= VERSIONS_PER_PACKAGE:
                break
            name = f"{package}-{version}"
            wheel = None
            for file_info in releases.get(version) or []:
                if file_info.get("packagetype") == "bdist_wheel":
                    wheel = file_info.get("url")
                    break
            if not wheel:
                skipped["no_wheel"] += 1
                continue
            document = fetch(SIDECAR.format(url=wheel), cache_dir / f"{name}.metadata")
            if document is None:
                # Not every file has a PEP 658 sidecar.
                skipped["no_wheel"] += 1
                continue
            text = document.decode("utf-8", "replace")
            if len(text) > MAX_DOCUMENT:
                skipped["larger_than_limit"] += 1
                continue
            if any(existing == name for existing, _ in documents):
                # Two entries of the corpus can name the same version (a project
                # listed twice); a case name has to be unique because the
                # divergence table is keyed by it.
                continue
            documents.append((name, text))
            taken += 1
        print(
            f"  {package}: {taken} documents "
            f"(running total {len(documents)}, skipped {skipped})",
            flush=True,
        )

    skipped["fetch_errors"] = len(fetch_errors)
    skipped["fetch_error_samples"] = fetch_errors[:20]
    return documents, skipped


def mbt_string(text: str) -> str:
    """A MoonBit string literal for one document or case name.

    Every control character is escaped, not just the three with a short spelling:
    MoonBit's lexer treats the vertical tab and the form feed as line breaks, so a
    raw one inside a literal ends that literal and turns the rest of the document
    into source. The `Keywords` whitespace case carries exactly those two, which is
    how this rule was found -- the emitter reported a four-field `meta` record for
    a document whose literal had been cut in half.
    """
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
            out.append("\\u{%x}" % ord(char))
        else:
            out.append(char)
    out.append('"')
    return "".join(out)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--offline", action="store_true", help="use the cached PyPI documents")
    args = parser.parse_args(argv)

    files = sorted(CASES.glob("*.metadata"))
    if not files:
        sys.exit(f"no cases under {CASES}")
    curated = [(path.stem, path.read_text(encoding="utf-8")) for path in files]

    print(f"{len(curated)} curated cases")
    real, skipped = real_documents(args.offline)
    print(f"{len(real)} real documents ({skipped})")

    divergences = read_divergences()
    known = {name for name, _ in curated} | {name for name, _ in real}
    for name, expected_accept in divergences:
        if name not in known:
            sys.exit(f"divergences.txt names an unknown case: {name}")
        text = dict(curated + real)[name]
        actual_accept, detail = reference_verdict(text)
        if actual_accept != expected_accept:
            sys.exit(
                f"divergences.txt claims {name} is `"
                f"{'accept' if expected_accept else 'reject'}` for the reference "
                f"implementation, but it {('accepts' if actual_accept else 'rejects')} it"
                + ("" if actual_accept else f" ({detail})")
            )

    lines = [
        "///|",
        "/// Core metadata (`METADATA` / `PKG-INFO`) conformance cases: the curated",
        "/// documents under `metadata_cases/`, one rule each. Every verdict used by",
        "/// the differential harness comes from PyPA `packaging` 26.3 at run time;",
        "/// this array carries the documents themselves.",
        "///",
        "/// Regenerate with tools/fetch_metadata_corpus.py; do not edit by hand.",
        "pub let metadata_cases : Array[(String, String)] = [",
    ]
    for name, text in curated:
        lines.append("  (%s, %s)," % (mbt_string(name), mbt_string(text)))
    lines.append("]")
    lines.append("")
    lines.append("///|")
    lines.append("/// Real `METADATA` documents served next to PyPI wheels (PEP 658 `.metadata`")
    lines.append("/// sidecars), named `<distribution>-<version>`. These are the documents a")
    lines.append(f"/// tool actually has to read; {skipped.get('larger_than_limit', 0)} were dropped for")
    lines.append(f"/// exceeding {MAX_DOCUMENT} characters and are counted in")
    lines.append("/// `fixtures/metadata_corpus.json` rather than silently omitted.")
    lines.append("pub let metadata_pypi_cases : Array[(String, String)] = [")
    for name, text in real:
        lines.append("  (%s, %s)," % (mbt_string(name), mbt_string(text)))
    lines.append("]")
    lines.append("")
    lines.append("///|")
    lines.append("/// Documents where this library deliberately answers differently from the")
    lines.append("/// reference implementation, as `(case name, does the reference accept it)`.")
    lines.append("/// `metadata_cases/divergences.txt` explains each one and is checked against")
    lines.append("/// the reference implementation when this fixture is generated, so an entry")
    lines.append("/// that stops being a divergence fails the generator instead of being")
    lines.append("/// tolerated. The harness asserts the two answers really do differ, in the")
    lines.append("/// recorded direction.")
    lines.append("pub let metadata_divergences : Array[(String, Bool)] = [")
    for name, expected_accept in divergences:
        lines.append('  (%s, %s),' % (mbt_string(name), "true" if expected_accept else "false"))
    lines.append("]")
    MBT.write_text("\n".join(lines) + "\n", encoding="utf-8")

    provenance = {
        "reference": "packaging 26.3 Metadata.from_email(data, validate=True)",
        "curated_count": len(curated),
        "pypi_count": len(real),
        "document_count": len(curated) + len(real),
        "divergences": [name for name, _ in divergences],
        "skipped": skipped,
        "documents": [
            {
                "name": name,
                "source": source,
                "bytes": len(text),
                "reference_accepts": reference_verdict(text)[0],
                "reference_detail": reference_verdict(text)[1][:200],
            }
            for source, group in (("curated", curated), ("pypi", real))
            for name, text in group
        ],
    }
    JSON_OUT.write_text(
        json.dumps(provenance, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    print(f"{len(curated) + len(real)} documents -> {MBT.name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
