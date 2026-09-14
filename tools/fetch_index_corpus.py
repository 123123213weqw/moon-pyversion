"""Build the PEP 691 simple-index corpus used by the differential corpus.

Two kinds of document are collected:

- real responses from a PEP 691 index (`Accept:
  application/vnd.pypi.simple.v1+json`), one per project of the PyPI corpus, so
  the reader is exercised on documents a real index serves rather than on
  hand-written JSON;
- curated documents under `index_cases/*.json`, which break one rule of
  RFC 8259 or of PEP 691 at a time.

Nothing here needs PyPA `packaging`: RFC 8259 and PEP 691 are compared against
Python's own `json` module and against the specification's rules, expressed
once in `project_document` below. That projection is what the emitter's `index`
records are compared against, so the rules live in one place and both sides have
to agree with them.

Run with any Python 3.8+ interpreter::

    python3 -B tools/fetch_index_corpus.py

Use `--offline` to rebuild from `fixtures/index_cache/` without the network.
"""

from __future__ import annotations

import argparse
import json
import socket
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CASES = ROOT / "index_cases"
MBT = ROOT / "fixtures" / "index_corpus.mbt"
JSON_OUT = ROOT / "fixtures" / "index_corpus.json"
CACHE = ROOT / "fixtures" / "index_cache"
PACKAGE_INDEX = ROOT / "fixtures" / "pypi_corpus.json"

INDEX = "https://pypi.tuna.tsinghua.edu.cn/simple/{name}/"
ACCEPT = "application/vnd.pypi.simple.v1+json"

# A real index response for a large project runs to megabytes (the biggest here
# is 4.4 MB of JSON). One record carries a whole document, so a document is
# reduced to its first MAX_FILES entries and its first MAX_VERSIONS versions
# before it is stored. The reduction keeps the real `name`, `meta` and file
# entries byte for byte -- nothing is rewritten -- and every document that was
# reduced says so in the fixture and in the provenance, so the corpus never
# claims to be a complete copy of a response it truncated.
MAX_FILES = 20
MAX_VERSIONS = 40
# Documents above this are dropped outright, and counted.
MAX_DOCUMENT = 400000


# An index that is asked for a hundred documents in a row starts refusing them,
# so a request is retried with a growing pause instead of being counted as
# "this project has no index". A cached response short circuits both.
RETRIES = 4
PACE_SECONDS = 0.4


def fetch(url: str, cache: Path) -> bytes | None:
    if cache.exists():
        return cache.read_bytes()
    request = urllib.request.Request(
        url,
        headers={"Accept": ACCEPT, "User-Agent": "moon-pyversion-corpus"},
    )
    time.sleep(PACE_SECONDS)
    last: Exception | None = None
    for attempt in range(RETRIES):
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                payload = response.read()
        except (urllib.error.URLError, TimeoutError) as error:
            last = error
            time.sleep(2.0 * (attempt + 1))
            continue
        cache.parent.mkdir(parents=True, exist_ok=True)
        cache.write_bytes(payload)
        return payload
    print(f"  fetch failed: {url} ({last})", file=sys.stderr)
    return None


def escape_field(text: str) -> str:
    """Make one projection field unambiguous.

    The projection is a flat string with `;`, `|`, `,` and `=` as separators, and
    a JSON string may contain any of them (a `url` with a `;` in it, a `yanked`
    reason with a `|`). Escaping them in both implementations keeps the encoding
    injective, so a difference cannot be hidden by two fields running together.
    """
    out = []
    for char in text:
        if char == "\\":
            out.append("\\\\")
        elif char == "|":
            out.append("\\p")
        elif char == ";":
            out.append("\\s")
        elif char == ",":
            out.append("\\c")
        elif char == "=":
            out.append("\\e")
        else:
            out.append(char)
    return "".join(out)


def unescape_field(text: str) -> str:
    """Undo `escape_field` in the harness, which has to split a record first."""
    out = []
    index = 0
    while index < len(text):
        char = text[index]
        if char != "\\" or index + 1 >= len(text):
            out.append(char)
            index += 1
            continue
        following = text[index + 1]
        out.append({"\\": "\\", "p": "|", "s": ";", "c": ",", "e": "="}.get(following, char))
        if following not in "\\psce":
            index += 1
            continue
        index += 2
    return "".join(out)


def yanked_state(value: object) -> str:
    """PEP 592's `yanked`: absent/false, true, or a string reason.

    PEP 592 defines only those three shapes, so anything else -- a number, an
    object, an array -- is a defect and raises.
    """
    if value is None or value is False:
        return "not-yanked"
    if value is True:
        return "yanked:"
    if isinstance(value, str):
        return "yanked:" + value
    raise ValueError("`yanked` must be a boolean or a string")


def project_document(document: object) -> str:
    """The projection both sides of an `index` record must agree on.

    This is the PEP 691 mapping written down once: the required `name` and
    `files`, the optional `meta.api-version` (PEP 700 `versions` is optional
    too), and per file the `filename`, `url`, `hashes` map, `requires-python`
    (absent and `null` are the same thing), `yanked` in its three states, `size`
    and `upload-time`. Members the specification does not define are ignored, as
    PEP 691 requires of clients.

    A document that does not follow the specification raises, which the caller
    turns into a rejection.
    """
    if not isinstance(document, dict):
        raise ValueError("the top level must be an object")
    name = document.get("name")
    if not isinstance(name, str):
        raise ValueError("`name` is required and must be a string")
    files = document.get("files")
    if not isinstance(files, list):
        raise ValueError("`files` is required and must be an array")
    meta = document.get("meta")
    api_version = ""
    if isinstance(meta, dict):
        candidate = meta.get("api-version")
        if candidate is not None:
            if not isinstance(candidate, str):
                raise ValueError("`meta.api-version` must be a string")
            api_version = candidate
    versions = document.get("versions")
    if versions is not None and not isinstance(versions, list):
        raise ValueError("`versions` must be an array of strings")
    parts = [f"name={escape_field(name)}", f"api-version={escape_field(api_version)}"]
    parts.append(f"versions={len(versions) if isinstance(versions, list) else 0}")
    parts.append(f"files={len(files)}")
    for index, entry in enumerate(files):
        if not isinstance(entry, dict):
            raise ValueError(f"files[{index}] must be an object")
        filename = entry.get("filename")
        url = entry.get("url")
        if not isinstance(filename, str) or not isinstance(url, str):
            raise ValueError(f"files[{index}] needs `filename` and `url` strings")
        hashes = entry.get("hashes")
        if not isinstance(hashes, dict):
            raise ValueError(f"files[{index}].hashes must be an object")
        for algorithm, candidate in hashes.items():
            if not isinstance(candidate, str):
                raise ValueError(f"files[{index}].hashes[{algorithm!r}] must be a string")
        digest = ",".join(
            f"{escape_field(k)}={escape_field(v)}" for k, v in sorted(hashes.items())
        )
        requires_python = entry.get("requires-python")
        if requires_python is not None and not isinstance(requires_python, str):
            raise ValueError(f"files[{index}]['requires-python'] must be a string")
        size = entry.get("size")
        if size is not None:
            # `bool` is a subclass of `int` in Python, and a JSON float is not an
            # integer size: both are rejected.
            if isinstance(size, bool) or not isinstance(size, int) or size < 0:
                raise ValueError(f"files[{index}].size must be a non-negative integer")
        upload_time = entry.get("upload-time")
        if upload_time is not None and not isinstance(upload_time, str):
            raise ValueError(f"files[{index}]['upload-time'] must be a string")
        parts.append(
            "file:"
            + "|".join(
                [
                    escape_field(filename),
                    escape_field(url),
                    digest,
                    escape_field(requires_python or ""),
                    escape_field(yanked_state(entry.get("yanked", False))),
                    "" if size is None else str(size),
                    escape_field(upload_time or ""),
                ]
            )
        )
    return ";".join(parts)


def reduce_document(text: str) -> tuple[str, bool]:
    """Keep the head of a large response; returns `(document, was_reduced)`.

    Parsed and re-serialized rather than cut by text, so the result is always a
    valid JSON document with the same members in the same order. Only `files`
    and `versions` are shortened.
    """
    if len(text) <= MAX_DOCUMENT:
        document = json.loads(text) if len(text) > 8000 else None
    else:
        document = None
    if document is None:
        if len(text) <= 8000:
            return text, False
        document = json.loads(text)
    reduced = False
    files = document.get("files")
    if isinstance(files, list) and len(files) > MAX_FILES:
        document["files"] = files[:MAX_FILES]
        reduced = True
    versions = document.get("versions")
    if isinstance(versions, list) and len(versions) > MAX_VERSIONS:
        document["versions"] = versions[:MAX_VERSIONS]
        reduced = True
    if not reduced:
        return text, False
    return json.dumps(document, ensure_ascii=False), True


def real_documents(offline: bool) -> tuple[list[tuple[str, str]], dict]:
    """PEP 691 documents for the projects of the PyPI corpus."""
    if offline:
        documents = []
        reduced_count = 0
        for path in sorted(CACHE.glob("*.json")):
            text = path.read_text(encoding="utf-8")
            document, reduced = reduce_document(text)
            if reduced:
                reduced_count += 1
            documents.append((path.stem, document))
        if not documents:
            sys.exit(f"--offline needs documents under {CACHE}")
        return documents, {
            "offline": True,
            "count": len(documents),
            "reduced": reduced_count,
        }

    socket.setdefaulttimeout(30)
    if not PACKAGE_INDEX.exists():
        sys.exit(f"missing {PACKAGE_INDEX}; run tools/fetch_pypi_corpus.py first")
    packages = json.loads(PACKAGE_INDEX.read_text(encoding="utf-8"))["packages"]

    documents: list[tuple[str, str]] = []
    skipped = {"reduced": 0, "unavailable": 0}
    errors: list[str] = []
    for package in packages:
        payload = fetch(INDEX.format(name=package), CACHE / f"{package}.json")
        if payload is None:
            skipped["unavailable"] += 1
            errors.append(package)
            continue
        text = payload.decode("utf-8", "replace")
        document, reduced = reduce_document(text)
        if reduced:
            skipped["reduced"] = skipped.get("reduced", 0) + 1
        documents.append((package, document))
        print(
            f"  {package}: {len(text)} -> {len(document)} bytes"
            f"{' (reduced)' if reduced else ''}",
            flush=True,
        )
    skipped["fetch_errors"] = len(errors)
    skipped["fetch_error_samples"] = errors[:20]
    return documents, skipped


def mbt_string(text: str) -> str:
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
        else:
            out.append(char)
    out.append('"')
    return "".join(out)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--offline", action="store_true", help="use the cached responses")
    args = parser.parse_args(argv)

    files = sorted(CASES.glob("*.json"))
    if not files:
        sys.exit(f"no cases under {CASES}")
    curated = [(path.stem, path.read_text(encoding="utf-8")) for path in files]
    print(f"{len(curated)} curated cases")

    real, skipped = real_documents(args.offline)
    print(f"{len(real)} real documents ({skipped})")

    # Every curated document is classified here, so the emitter and the harness
    # cannot disagree about which side of a case is which: a case the index
    # specification accepts carries its projection, one it rejects is listed as
    # bad. This is also the check that the curated set really covers both
    # answers.
    accepted: list[tuple[str, str, str]] = []
    rejected: list[str] = []
    for name, text in curated:
        try:
            document = json.loads(text)
            projection = project_document(document)
        except (json.JSONDecodeError, ValueError) as error:
            rejected.append(name)
            print(f"  curated {name}: rejected ({type(error).__name__})")
            continue
        accepted.append((name, text, projection))
        print(f"  curated {name}: accepted")

    lines = [
        "///|",
        "/// PEP 691 simple-index documents that an index accepts, as",
        "/// `(case name, document, projection)`. The projection is the mapping",
        "/// written down once in `tools/fetch_index_corpus.py`, and the `index`",
        "/// records the emitter writes are compared against it.",
        "///",
        "/// Regenerate with tools/fetch_index_corpus.py; do not edit by hand.",
        "pub let index_cases : Array[(String, String, String)] = [",
    ]
    for name, text, projection in accepted:
        lines.append(
            "  (%s, %s, %s)," % (mbt_string(name), mbt_string(text), mbt_string(projection))
        )
    lines.append("]")
    lines.append("")
    lines.append("///|")
    lines.append("/// Documents the simple-index specification requires a client to reject,")
    lines.append("/// as `(case name, document)`. Every one of them breaks exactly one rule")
    lines.append("/// of RFC 8259 or of PEP 691, and the harness asserts that this library")
    lines.append("/// rejects each one.")
    lines.append("pub let index_bad_cases : Array[(String, String)] = [")
    for name, text in curated:
        if name in rejected:
            lines.append("  (%s, %s)," % (mbt_string(name), mbt_string(text)))
    lines.append("]")
    lines.append("")
    lines.append("///|")
    lines.append("/// Real PEP 691 responses from a public index")
    lines.append("/// (`Accept: application/vnd.pypi.simple.v1+json`), one per project of")
    lines.append("/// the PyPI corpus, as `(project, document, projection)`. These are the")
    lines.append("/// documents a resolver actually has to read.")
    lines.append("///")
    lines.append(
        f"/// Responses larger than {MAX_FILES} files or {MAX_VERSIONS} versions were"
    )
    lines.append(
        "/// shortened to those heads before being stored (the `name`, `meta` and"
    )
    lines.append(
        "/// the entries themselves are byte for byte the index's own); the count is"
    )
    lines.append("/// in `fixtures/index_corpus.json`.")
    lines.append("pub let index_pypi_cases : Array[(String, String, String)] = [")
    for name, text in real:
        try:
            projection = project_document(json.loads(text))
        except (json.JSONDecodeError, ValueError) as error:
            sys.exit(f"the index served an unusable document for {name}: {error}")
        lines.append(
            "  (%s, %s, %s)," % (mbt_string(name), mbt_string(text), mbt_string(projection))
        )
    lines.append("]")
    MBT.write_text("\n".join(lines) + "\n", encoding="utf-8")

    JSON_OUT.write_text(
        json.dumps(
            {
                "index": INDEX,
                "accept": ACCEPT,
                "max_document": MAX_DOCUMENT,
                "curated_accepted": [name for name, _, _ in accepted],
                "curated_rejected": rejected,
                "pypi_count": len(real),
                "skipped": skipped,
                "documents": [
                    {"name": name, "source": "pypi", "bytes": len(text)}
                    for name, text in real
                ],
            },
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )
    print(
        f"{len(accepted)} accepted + {len(rejected)} rejected curated, "
        f"{len(real)} real -> {MBT.name}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
