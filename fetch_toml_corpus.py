"""Generate the TOML conformance fixture used by the differential corpus.

Reads `toml_cases/*.toml`, asks `tomli` (the reference TOML 1.0 reader) whether
each one parses, and writes the cases into a MoonBit fixture array together with
the expected verdict and, for accepted documents, a canonical serialization of
the parsed value that both sides must agree on.

Run with the reference interpreter::

    /tmp/tomlvenv/bin/python -B tools/fetch_toml_corpus.py
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

try:
    import tomli
except ImportError:  # pragma: no cover
    sys.exit("tomli is required: install it in a throwaway venv")

ROOT = Path(__file__).resolve().parents[1]
CASES = ROOT / "toml_cases"
LENIENCIES = CASES / "leniencies.txt"
MBT = ROOT / "fixtures" / "toml_corpus.mbt"
JSON_OUT = ROOT / "fixtures" / "toml_corpus.json"


def canonical(value: object) -> str:
    """A side-effect free rendering of a parsed TOML value.

    Types are spelled out so an integer can never be confused with a float, and
    datetimes are rendered as their source text, which `tomli` preserves.
    """
    if isinstance(value, bool):
        return "bool:" + ("true" if value else "false")
    if isinstance(value, int):
        return "int:" + str(value)
    if isinstance(value, float):
        return "float:" + repr(value)
    if isinstance(value, str):
        return "str:" + value.replace("\\", "\\\\").replace("\n", "\\n")
    if isinstance(value, (list, tuple)):
        return "array:[" + ",".join(canonical(item) for item in value) + "]"
    if isinstance(value, dict):
        parts = []
        for key, item in value.items():
            parts.append(quote_key(key) + "=" + canonical(item))
        return "table:{" + ",".join(parts) + "}"
    if hasattr(value, "isoformat"):
        return "datetime:" + str(value)
    raise TypeError(f"unsupported TOML value {value!r}")


def quote_key(key: str) -> str:
    if re.fullmatch(r"[A-Za-z0-9_-]+", key):
        return key
    return json.dumps(key)


def read_leniencies() -> list[str]:
    """Case names where the reference reader is looser than TOML 1.0."""
    if not LENIENCIES.exists():
        return []
    names = []
    for line in LENIENCIES.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            names.append(line)
    return names


def main() -> int:
    files = sorted(CASES.glob("*.toml"))
    if not files:
        sys.exit(f"no cases under {CASES}")
    leniencies = read_leniencies()

    records = []
    accepted = 0
    rejected = 0
    for path in files:
        name = path.stem
        text = path.read_text(encoding="utf-8")
        try:
            parsed = tomli.loads(text)
        except tomli.TOMLDecodeError:
            records.append((name, text, False, ""))
            rejected += 1
            continue
        records.append((name, text, True, canonical(parsed)))
        accepted += 1

    # Every declared leniency must name a real case that the reference reader
    # really does accept, so the list cannot go stale unnoticed.
    known = {name for name, _, _, _ in records}
    for name in leniencies:
        if name not in known:
            sys.exit(f"leniencies.txt names an unknown case: {name}")
        entry = next(item for item in records if item[0] == name)
        if not entry[2]:
            sys.exit(
                f"leniencies.txt claims {name} is a leniency, "
                "but the reference reader rejects it"
            )

    lines = [
        "///|",
        "/// TOML 1.0 conformance cases with the verdict of the reference reader",
        "/// (`tomli`). Each entry is `(name, document, accepted, canonical value)`;",
        "/// a rejected document carries an empty canonical value.",
        "///",
        "/// Regenerate with tools/fetch_toml_corpus.py; do not edit by hand.",
        "pub let toml_cases : Array[(String, String, Bool, String)] = [",
    ]
    for name, text, ok, value in records:
        lines.append(
            '  ("%s", %s, %s, %s),'
            % (name, mbt_string(text), "true" if ok else "false", mbt_string(value))
        )
    lines.append("]")
    lines.append("")
    lines.append("///|")
    lines.append("/// Case names where TOML 1.0 requires a rejection but the reference")
    lines.append("/// reader accepts one. See `toml_cases/leniencies.txt` for the reason.")
    lines.append("pub let toml_leniencies : Array[String] = [")
    for name in leniencies:
        lines.append('  "%s",' % name)
    lines.append("]")
    MBT.write_text("\n".join(lines) + "\n", encoding="utf-8")

    JSON_OUT.write_text(
        json.dumps(
            {
                "reference": "tomli " + getattr(tomli, "__version__", "?"),
                "case_count": len(records),
                "accepted_count": accepted,
                "rejected_count": rejected,
                "leniencies": leniencies,
                "cases": [
                    {"name": name, "accepted": ok, "canonical": value}
                    for name, _, ok, value in records
                ],
            },
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )
    print(f"{len(records)} cases ({accepted} accepted, {rejected} rejected) -> {MBT.name}")
    return 0


def mbt_string(text: str) -> str:
    """A MoonBit string literal, escaping backslashes and the quote characters."""
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


if __name__ == "__main__":
    raise SystemExit(main())
