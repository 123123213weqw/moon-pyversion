"""Generate the upgrade-shortlist corpus (scenario 3).

`examples/upgrade-check` answers "which of these candidates is worth testing?"
from a current version, a target range and a candidate list. That is a decision,
so it can be checked the way `resolve` is: the same inputs are put to
`packaging`, and the two sides must agree on the shortlist *and* on why every
other candidate was dropped.

The payload is textual so both sides decode it identically:

    ``<current>|<target spec>|<mode>|<python>|<candidate>;<candidate>;...``

A candidate is ``<version>`` or ``<version>@<requires-python>``. ``;`` and ``@``
are safe separators: neither can appear in a version, and a specifier may contain
commas and spaces but not a semicolon. An empty target spec means "any version",
and an empty field is a real case throughout.

The rules, in the order they are applied -- the first one that fires is the reason
the report prints:

1. the current version or the target range does not parse -> the whole case is
   fatal, with a stable code (``!UNPARSABLE_CURRENT``, ``!BAD_TARGET``);
2. the candidate does not parse as a PEP 440 version -> ``unparsable``;
3. it is not newer than the current version -> ``same`` or ``downgrade``;
4. it falls outside the target range -> ``out-of-range``;
5. it is inside the range but the prerelease policy holds it back ->
   ``prerelease``. The policy is `SpecifierSet.filter`'s, which is what makes
   ``auto`` mode interesting: prereleases are admitted only when the range
   admits nothing else. The fallback looks at the candidates that are *newer* and
   inside the range, because those are the ones a report is about;
6. its ``requires-python`` excludes the target interpreter ->
   ``requires-python``. An unreadable ``requires-python`` is ignored rather than
   treated as a rejection, which is what pip does and what this library's own
   resolver already does.

Everything else is kept, and the shortlist is ordered *ascending*: the smallest
step first is the one to test first. Rejected candidates keep their input order,
so the report reads like the list the caller handed over. The projection carries
both halves, so a side that drops a candidate for the wrong reason fails even
when the shortlist itself matches.

Run with the reference interpreter::

    ~/oracle-versions/venv26.3/bin/python -B tools/fetch_upgrade_corpus.py
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path

try:
    from packaging.specifiers import SpecifierSet
    from packaging.version import Version
except ImportError as error:  # pragma: no cover
    raise SystemExit(f"packaging is required: {error}") from error

ROOT = Path(__file__).resolve().parents[1]
MBT = ROOT / "fixtures" / "upgrade_corpus.mbt"
JSON_OUT = ROOT / "fixtures" / "upgrade_corpus.json"

# Case name -> payload. The names describe the situation, because a failure
# message that says "compatible-bump-admitted" is worth more than "case 41".
CASES: list[tuple[str, str]] = [
    # --- the shape of a normal shortlist
    ("no-target-range", "1.0.0||auto|3.11|1.0.0;1.1.0;2.0.0;0.9.0"),
    ("patch-and-minor-only", "1.2.3|>=1.2.3,<2.0|auto|3.11|1.2.4;1.3.0;2.0.0;1.2.2"),
    ("target-range-is-a-window", "1.0|>=1.5,<1.8|auto|3.11|1.4;1.5;1.6.1;1.7;1.8;1.9"),
    ("upper-bound-excludes-the-boundary", "1.0|<2.0|auto|3.11|1.9.9;2.0;2.0.1"),
    ("lower-bound-includes-the-current", "1.0|>=1.0|auto|3.11|1.0;1.0.1"),
    ("lower-bound-excludes-the-current", "1.0|>1.0|auto|3.11|1.0;1.0.1"),
    ("every-candidate-out-of-range", "1.0|>=2.0|auto|3.11|1.0.1;1.5"),
    ("one-candidate-only", "0.1|>=0.2|auto|3.11|0.2"),
    ("no-candidates", "1.0|>=1.0|auto|3.11|"),
    ("nothing-newer-than-the-current", "9.9||auto|3.11|1.0;2.0"),
    # --- ordering: ascending, and ties broken by the raw spelling
    ("shortlist-is-ascending", "1.0|>=1.0|auto|3.11|1.9;1.2;1.5;1.10"),
    ("duplicate-spellings-of-one-version", "1.0||auto|3.11|1.1;1.1.0;1.1.0.0"),
    ("local-versions-order-after-their-release", "1.0||auto|3.11|1.1;1.1+local"),
    ("normalized-equal-version-is-not-an-upgrade", "1.5.0||auto|3.11|1.5;1.5.0"),
    ("epoch-makes-a-version-newer", "1.0||auto|3.11|1!0.1;1.0.1"),
    ("epoch-on-the-current-version", "1!1.0||auto|3.11|1!1.1;2.0"),
    # --- downgrades and equal versions
    ("equal-version-is-not-an-upgrade", "1.5||auto|3.11|1.4;1.5;1.6"),
    ("downgrade-only", "2.0||auto|3.11|1.9;1.0;0.1"),
    # --- prereleases: the three modes on the same input
    ("prerelease-auto-dropped-when-a-final-exists", "1.0|>=1.0|auto|3.11|1.1b1;1.1"),
    ("prerelease-auto-kept-when-none-else-exists", "1.0|>=1.0|auto|3.11|1.1b1"),
    ("prerelease-any-keeps-them", "1.0|>=1.0|any|3.11|1.1b1;1.1"),
    ("prerelease-none-drops-them", "1.0|<2.0|none|3.11|1.1b1;1.1;1.2rc1;1.2"),
    ("prerelease-excluded-by-the-range", "1.0|<2.0|any|3.11|2.0b1;1.9"),
    ("dev-release-under-auto", "1.0||auto|3.11|1.1.dev1;1.0.1"),
    ("post-release-is-not-a-prerelease", "1.0|>=1.0|none|3.11|1.0.post1;1.0.1"),
    ("prerelease-only-and-none-mode", "1.0||none|3.11|1.1b1;1.2rc1"),
    ("range-mentions-a-prerelease-so-auto-admits", "1.0|>=1.1b1|auto|3.11|1.1b1;1.1"),
    # --- requires-python on the candidate
    ("requires-python-admits-the-target", "1.0||auto|3.11|1.1@>=3.8;1.2@>=3.8"),
    ("requires-python-excludes-the-target", "1.0||auto|3.11|1.1@>=3.12;1.2@<3.11"),
    ("requires-python-missing-means-any", "1.0||auto|3.11|1.1;1.2@>=3.8"),
    ("requires-python-with-a-window", "1.0||auto|3.11|1.1@>=3.8,<4;1.2@>=3.11,<3.12"),
    ("requires-python-equal-boundary-is-admitted", "1.0||auto|3.11|1.1@>=3.11"),
    ("requires-python-prerelease-target", "1.0||auto|3.12.0rc1|1.1@>=3.12"),
    ("requires-python-on-an-old-interpreter", "1.0||auto|3.7|1.1@>=3.6;1.2@>=3.8"),
    ("unreadable-requires-python-is-ignored", "1.0||auto|3.11|1.1@not-a-specifier"),
    # --- rejected candidates keep their reason, in input order
    ("unparsable-candidate", "1.0||auto|3.11|1.1;not-a-version;1.2"),
    ("rejected-candidates-keep-input-order", "1.5|>=1.5,<2.0|auto|3.11|1.4;2.5;1.6;1.5"),
    ("every-reason-at-once", "1.5|>=1.5,<2.0|auto|3.11|nope;1.4;2.5;1.6@>=3.12;1.7"),
    ("reason-order-prefers-the-earlier-rule", "1.5|>=1.5|auto|3.11|1.4@>=3.12;2.0@>=3.12"),
    ("unparsable-candidate-that-is-also-old", "1.5||auto|3.11|nope;1.4"),
    # --- fatal inputs
    ("unparsable-current", "not-a-version||auto|3.11|1.1;1.2"),
    ("bad-target-range", "1.0|not-a-specifier|auto|3.11|1.1;1.2"),
    ("empty-current-version", "||auto|3.11|1.0;2.0"),
    # --- the range forms that make a window
    ("compatible-release-form", "1.0|~=1.4.2|auto|3.11|1.4.2;1.4.9;1.5;1.4.1"),
    ("exclusion-form", "1.0|>=1.0,!=1.2|auto|3.11|1.1;1.2;1.3"),
    ("wildcard-form", "1.0|==1.4.*|auto|3.11|1.3.9;1.4;1.4.9;1.5"),
    ("arbitrary-equality-form", "1.0|===1.5|auto|3.11|1.5;1.5.0;1.6"),
    ("two-sided-window", "1.0|>=1.0,<1.3|auto|3.11|1.2.9;1.3;2.0"),
    # --- bigger mixed cases
    (
        "realistic-flask-style-window",
        "2.3.0|>=2.3,<3.0|auto|3.11|"
        "2.3.0;2.3.1;2.3.2;2.3.3;3.0.0;3.1.0;2.4.0rc1;2.4.0;2.2.5;2.5.0@>=3.12",
    ),
    (
        "realistic-mixed-with-everything",
        "1.26.0|>=1.26,<2.0|auto|3.11|"
        "1.26.0;1.26.1;1.26.2;1.26.3;1.26.4;1.27.0rc1;1.27.0;2.0.0;1.25.2;bad;1.28.0@>=3.13",
    ),
    (
        "realistic-prerelease-heavy",
        "0.9.0|>=0.9|auto|3.10|"
        "0.9.0;1.0.0a1;1.0.0b1;1.0.0rc1;1.0.0;1.1.0.dev1;1.1.0;2.0.0",
    ),
]


def parse_version_text(text: str) -> Version | None:
    if text == "":
        return None
    try:
        return Version(text)
    except Exception:  # noqa: BLE001 - the reference must answer, not raise
        return None


def prereleases_setting(mode: str) -> bool | None:
    if mode == "auto":
        return None
    if mode == "any":
        return True
    if mode == "none":
        return False
    raise ValueError(f"unknown prerelease mode {mode!r}")


def split_candidates(text: str) -> list[tuple[str, str | None]]:
    """`v1@rp;v2` -> `[("v1", "rp"), ("v2", None)]`."""
    if text == "":
        return []
    out: list[tuple[str, str | None]] = []
    for piece in text.split(";"):
        if "@" in piece:
            version, _, requires_python = piece.partition("@")
            out.append((version, requires_python))
        else:
            out.append((piece, None))
    return out


def project(
    current_text: str,
    target_text: str,
    mode: str,
    python_text: str,
    candidates_text: str,
) -> str:
    """The shortlist and the rejection reasons; both sides must agree on this."""
    current = parse_version_text(current_text)
    if current is None:
        return "!UNPARSABLE_CURRENT"
    target = None
    if target_text != "":
        try:
            target = SpecifierSet(target_text)
        except Exception:  # noqa: BLE001
            return "!BAD_TARGET"
    prereleases = prereleases_setting(mode)
    python = parse_version_text(python_text)

    # Step 1: candidates that parse and are strictly newer, in input order.
    newer: list[tuple[Version, str, str | None]] = []
    rejected: list[str] = []
    for raw, requires_python in split_candidates(candidates_text):
        version = parse_version_text(raw)
        if version is None:
            rejected.append(f"{raw}=unparsable")
            continue
        if version == current:
            rejected.append(f"{raw}=same")
            continue
        if version < current:
            rejected.append(f"{raw}=downgrade")
            continue
        newer.append((version, raw, requires_python))

    # Step 2: the range and the prerelease policy, decided by the reference's own
    # `filter` -- including its "admit prereleases only if nothing else matched"
    # fallback, which is what makes `auto` different from `any` and `none`.
    versions = [version for version, _raw, _rp in newer]
    if target is None:
        admitted = {id(version) for version in versions}
        contained = set(admitted)
    else:
        contained = {
            id(version)
            for version in versions
            if target.contains(version, prereleases=True)
        }
        admitted = {
            id(version) for version in target.filter(versions, prereleases=prereleases)
        }

    kept: list[tuple[Version, str]] = []
    for version, raw, requires_python in newer:
        if id(version) not in contained:
            rejected.append(f"{raw}=out-of-range")
            continue
        if id(version) not in admitted:
            rejected.append(f"{raw}=prerelease")
            continue
        if requires_python is not None and python is not None:
            try:
                allowed = SpecifierSet(requires_python)
            except Exception:  # noqa: BLE001 - an unreadable value is ignored, like pip
                allowed = None
            if allowed is not None and not allowed.contains(python, prereleases=True):
                rejected.append(f"{raw}=requires-python")
                continue
        kept.append((version, raw))

    kept.sort(key=lambda entry: (entry[0], entry[1]))
    kept_text = ",".join(raw for _version, raw in kept)
    return f"{kept_text}|{';'.join(rejected)}"


def encode(text: str) -> str:
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


def build_fixture() -> tuple[str, list[tuple[str, str, str]]]:
    seen: set[str] = set()
    records: list[tuple[str, str, str]] = []
    for name, payload in CASES:
        if name in seen:
            sys.exit(f"duplicate upgrade case name: {name}")
        seen.add(name)
        fields = payload.split("|")
        if len(fields) != 5:
            sys.exit(f"{name}: payload needs five fields, got {len(fields)}")
        projection = project(*fields)
        if projection.startswith("!") and "!" not in name.replace("!", ""):
            # Fatal cases are deliberately rare; name them so a reader can tell
            # an expected fatal from a typo in the payload.
            pass
        records.append((name, payload, projection))

    fatal = [name for name, _p, projection in records if projection.startswith("!")]
    lines = [
        "///|",
        "/// Upgrade-shortlist cases for `examples/upgrade-check`. Each entry is",
        "/// `(name, payload, projection)`; the payload is",
        "/// `<current>|<target spec>|<mode>|<python>|<candidate>;<candidate>` and the",
        "/// projection is `<shortlist, ascending>|<rejected as v=reason;...>`, or a",
        "/// `!CODE` when the whole case cannot be decided.",
        "///",
        "/// Regenerate with tools/fetch_upgrade_corpus.py; do not edit by hand.",
        "pub let upgrade_cases : Array[(String, String, String)] = [",
    ]
    for name, payload, projection in records:
        lines.append(
            "  (%s, %s, %s)," % (encode(name), encode(payload), encode(projection))
        )
    lines.append("]")
    lines.append("")
    lines.append("///|")
    lines.append("/// Case names whose inputs cannot be decided at all, so both sides report")
    lines.append("/// a stable code instead of a shortlist.")
    lines.append("pub let upgrade_fatal_cases : Array[String] = [")
    for name in fatal:
        lines.append("  %s," % encode(name))
    lines.append("]")
    lines.append("")
    return "\n".join(lines) + "\n", records


def format_with_moon(path: Path) -> str | None:
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

    fixture, records = build_fixture()

    if args.check:
        before = MBT.read_text(encoding="utf-8") if MBT.exists() else ""
        try:
            MBT.write_text(fixture, encoding="utf-8")
            formatted = format_with_moon(MBT)
        finally:
            MBT.write_text(before, encoding="utf-8")
        if formatted is None:
            return 2
        if before != formatted:
            print(f"{MBT} is not what tools/fetch_upgrade_corpus.py generates")
            print("regenerate it, then run `moon fmt` on it and commit both")
            return 1
        print(f"{MBT} is up to date")
        return 0

    MBT.write_text(fixture, encoding="utf-8")
    JSON_OUT.write_text(
        json.dumps(
            {
                "reference": "packaging",
                "case_count": len(records),
                "cases": [
                    {"name": name, "payload": payload, "projection": projection}
                    for name, payload, projection in records
                ],
            },
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )
    with_shortlist = sum(
        1 for _n, _p, projection in records if not projection.startswith("!") and projection.split("|")[0]
    )
    fatal = sum(1 for _n, _p, projection in records if projection.startswith("!"))
    print(
        f"{len(records)} upgrade cases ({with_shortlist} with a non-empty shortlist, "
        f"{fatal} fatal) -> {MBT.name}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
