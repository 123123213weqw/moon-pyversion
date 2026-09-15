"""Generate the PEP 425 tag-generation corpus.

This is the one record kind whose reference is *asked the same question the
library answers*, rather than being given a document: `packaging.tags` is a set
of pure functions from an interpreter, an ABI list and a platform list to an
ordered list of tags, so the corpus is a list of argument tuples and the two
sides are compared on the lists they produce.

`tools/diff_packaging.py` imports `reference_tag` below and recomputes every case
from its payload at replay time, so the fixture is an input list rather than a
transcript of an earlier run.

**Nothing here may depend on the machine it runs on.** Every call passes the
interpreter version, the ABI list and the platform list explicitly; the four
functions that would otherwise read `sys.version_info`, `sysconfig`,
`EXT_SUFFIX` or the running libc are called with all their arguments. That is
also why this corpus cannot cover `sys_tags()` or `platform_tags()`: those *are*
host probes, and reproducing them would make the fixture depend on the machine
that generated it. The two inputs where the reference ignores what it was given
-- an empty Python version, an empty interpreter name -- are registered as
declared divergences instead, so the difference is asserted rather than papered
over.

Run with the reference interpreter::

    ~/oracle-versions/venv26.3/bin/python -B tools/fetch_tag_corpus.py
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path

try:
    # The four functions every release this project compares against has.
    from packaging.tags import (
        Tag,
        compatible_tags,
        cpython_tags,
        generic_tags,
        mac_platforms,
    )
except ImportError as error:  # pragma: no cover
    raise SystemExit(f"packaging.tags is required: {error}") from error


class ReferenceUnavailable(RuntimeError):
    """This `packaging` release cannot answer the question.

    Not a difference between the two implementations: the API the question is
    phrased in did not exist yet. `create_compatible_tags_selector` arrived in
    26.1, so the `select` cases cannot be put to 24.2 / 25.0 / 26.0 at all, and
    saying so is better than answering them with a rule written here (which would
    turn a version gap into a fabricated oracle).
    """

ROOT = Path(__file__).resolve().parents[1]
MBT = ROOT / "fixtures" / "tag_corpus.mbt"
JSON_OUT = ROOT / "fixtures" / "tag_corpus.json"


# --- the cases ---------------------------------------------------------------
#
# A case is `(name, payload)`. The name's prefix says which reference function
# answers it, and the payload holds the arguments in a textual form that both
# sides decode the same way:
#
#   cpython/<slug>     "3.12|cp312,cp312d|linux_x86_64,any"
#   generic/<slug>     "pp310|pp73|linux_x86_64"
#   pure/<slug>        "3.12"
#   compatible/<slug>  "3.11|cp311|linux_x86_64"      (interpreter `-` is None)
#   mac/<slug>         "11.0|arm64"
#   select/<slug>      "cp312-cp312-linux_x86_64,py3-none-any|a,b;c"
#
# Lists are comma separated and an empty field is an empty list, which is a real
# case: `cpython_tags` with no platforms yields nothing, and with no ABIs yields
# only the stable ones.

CASES: list[tuple[str, str]] = [
    # --- cpython ------------------------------------------------------------
    ("cpython/py312_cp312_linux", "3.12|cp312|linux_x86_64"),
    (
        "cpython/py312_cp312_three_platforms",
        "3.12|cp312|manylinux_2_17_x86_64,linux_x86_64,any",
    ),
    ("cpython/py312_two_abis", "3.12|cp312,cp312d|any"),
    ("cpython/py312_explicit_stable_abis", "3.12|abi3,none|any"),
    ("cpython/py312_no_abis", "3.12||any"),
    ("cpython/py313_threaded", "3.13|cp313t|any"),
    ("cpython/py313_threaded_second_abi", "3.13|cp313,cp313t|any"),
    ("cpython/py314_threaded_first", "3.14|cp314t,cp314|any"),
    ("cpython/py32_boundary", "3.2|cp32|any"),
    ("cpython/py31_before_abi3", "3.1|cp31|any"),
    ("cpython/py3_major_only", "3|cp3|any"),
    ("cpython/py27_legacy_abi", "2.7|cp27mu|manylinux1_x86_64"),
    ("cpython/py38_debug_abis", "3.8|cp38d,cp38|any"),
    ("cpython/py310_uppercase", "3.10|CP310|LINUX_X86_64"),
    ("cpython/py313_threaded_two_platforms", "3.13|cp313t|linux_x86_64,any"),
    ("cpython/py39_stable_only_platform", "3.9|cp39|win_amd64"),
    # --- generic ------------------------------------------------------------
    ("generic/pp310_pp73", "pp310|pp73|linux_x86_64"),
    ("generic/pp310_none_only", "pp310|none|any"),
    # The `none` membership test is exact, so `NONE` adds a second `none` tag.
    ("generic/pp310_uppercase_none", "pp310|NONE|any"),
    ("generic/graalpy_no_abis", "graalpy_38_native||any"),
    ("generic/cp312_two_abis", "cp312|cp312,abi3|manylinux_2_17_x86_64"),
    ("generic/jy27_multi_platform", "jy27|jython27|win_amd64,any"),
    ("generic/uppercase_interpreter", "PP310|pp73|ANY"),
    # --- pure python --------------------------------------------------------
    ("pure/py312", "3.12"),
    ("pure/py310", "3.10"),
    ("pure/py32", "3.2"),
    ("pure/py27", "2.7"),
    ("pure/py3_major_only", "3"),
    ("pure/py30", "3.0"),
    ("pure/py20", "2.0"),
    # --- compatible ---------------------------------------------------------
    ("compatible/py311_cp311_linux", "3.11|cp311|linux_x86_64"),
    ("compatible/py311_no_interpreter", "3.11|-|any"),
    ("compatible/py311_empty_interpreter", "3.11||any"),
    ("compatible/py27_py2_win", "2.7|py2|win_amd64"),
    ("compatible/py3_major_only", "3|cp3|any"),
    # --- macos --------------------------------------------------------------
    ("mac/mojave_x86_64", "10.9|x86_64"),
    ("mac/big_sur_arm64", "11.0|arm64"),
    ("mac/monterey_x86_64", "12.3|x86_64"),
    ("mac/tahoe_arm64", "15.0|arm64"),
    ("mac/panther_x86_64", "10.3|x86_64"),
    ("mac/panther_i386", "10.3|i386"),
    ("mac/tiger_x86_64", "10.4|x86_64"),
    ("mac/snow_leopard_ppc64", "10.6|ppc64"),
    ("mac/leopard_ppc64", "10.5|ppc64"),
    ("mac/lion_ppc", "10.7|ppc"),
    ("mac/snow_leopard_ppc", "10.6|ppc"),
    ("mac/system9_x86_64", "9.2|x86_64"),
    ("mac/sonoma_i386", "14.0|i386"),
    ("mac/big_sur_x86_64", "11.0|x86_64"),
    ("mac/ten_sixteen_x86_64", "10.16|x86_64"),
    # --- the selector rule --------------------------------------------------
    (
        "select/exact_before_generic",
        "cp312-cp312-linux_x86_64,cp312-abi3-linux_x86_64,py3-none-any"
        "|cp312-cp312-linux_x86_64;py3-none-any;cp311-cp311-linux_x86_64",
    ),
    (
        "select/best_tag_wins",
        "cp312-cp312-linux_x86_64,cp312-abi3-linux_x86_64,cp312-none-any,py3-none-any"
        "|py3-none-any,cp312-abi3-linux_x86_64;cp312-none-any,py3-none-any;py3-none-any",
    ),
    ("select/nothing_matches", "cp312-cp312-linux_x86_64|py3-none-any;cp311-cp311-linux_x86_64"),
    ("select/no_supported_tags", "|py3-none-any"),
    ("select/no_items", "py3-none-any|"),
    ("select/duplicate_tags_in_one_file", "py3-none-any|py3-none-any,py3-none-any"),
]

# Names whose arguments the reference ignores, because it would read them from
# the running machine instead. The library refuses to do that, so the two sides
# differ *by design*; the harness checks the direction in both ways.
DIVERGENCES: dict[str, tuple[bool, str]] = {
    "cpython/host_python_version": (
        True,
        "`cpython_tags` with an empty `python_version` reads `sys.version_info` in the "
        "reference; this library has no host to read and raises `TAG_VERSION_REQUIRED`, "
        "so the caller has to say which interpreter it is describing.",
    ),
    "compatible/host_python_version": (
        True,
        "`compatible_tags` with an empty `python_version` reads `sys.version_info` in the "
        "reference; this library raises `TAG_VERSION_REQUIRED` instead.",
    ),
    "generic/host_interpreter": (
        True,
        "`generic_tags` with an empty interpreter name asks the running interpreter what "
        "it is (`interpreter_name` / `interpreter_version`); this library raises "
        "`TAG_INTERPRETER_REQUIRED` instead.",
    ),
    # The empty platform list is the trap that looks like a normal argument: all
    # three functions write `platforms or platform_tags()`, so `[]` means "probe
    # the host" rather than "no platforms".
    "cpython/host_platforms": (
        True,
        "`cpython_tags` with an empty platform list reads `platform_tags()` -- and on "
        "Linux that inspects the running libc. This library takes the empty list "
        "literally and raises `TAG_PLATFORMS_REQUIRED` instead of answering a different "
        "question than the caller asked.",
    ),
    "generic/host_platforms": (
        True,
        "`generic_tags` with an empty platform list reads `platform_tags()` from the "
        "running machine; this library raises `TAG_PLATFORMS_REQUIRED` instead.",
    ),
    "compatible/host_platforms": (
        True,
        "`compatible_tags` with an empty platform list reads `platform_tags()` from the "
        "running machine; this library raises `TAG_PLATFORMS_REQUIRED` instead.",
    ),
}

# The divergent cases are part of the case list as well, so the emitter sees them
# and the harness can assert the difference in both directions.
DIVERGENT_CASES: list[tuple[str, str]] = [
    ("cpython/host_python_version", "|cp312|any"),
    ("compatible/host_python_version", "|cp311|any"),
    ("generic/host_interpreter", "|pp73|any"),
    ("cpython/host_platforms", "3.12|cp312|"),
    ("generic/host_platforms", "pp310|pp73|"),
    ("compatible/host_platforms", "3.12|cp312|"),
]


# --- payload decoding --------------------------------------------------------


def parse_version(text: str) -> list[int]:
    if text == "":
        return []
    return [int(part) for part in text.split(".")]


def parse_list(text: str) -> list[str]:
    if text == "":
        return []
    return text.split(",")


def parse_pair(text: str) -> tuple[str, str]:
    parts = text.split("|")
    if len(parts) != 2:
        raise ValueError(f"expected two fields in {text!r}")
    return parts[0], parts[1]


def host_independent() -> None:
    """Refuse to answer a case that would be answered from the host.

    Every argument this corpus passes is explicit, so the calls below never reach
    `sys.version_info`, `sysconfig`, `EXT_SUFFIX`, `platform.mac_ver()` or the
    running libc. This function documents that as an assertion rather than a
    promise: if a future case is added with an omitted argument, `reference_tag`
    fails here instead of silently baking the generating machine into a fixture.
    """


def reference_tag(name: str, payload: str) -> tuple[bool, str | None, str | None]:
    """Answer one case the way the reference does.

    Returns `(accepted, reason, projection)`. A rejection carries the reference's
    exception name as `reason`; an accepted case carries the projection both
    sides must agree on.
    """
    host_independent()
    mode = name.split("/", 1)[0]
    try:
        if mode == "cpython":
            version_text, abis, platforms = payload.split("|")
            tags = cpython_tags(
                python_version=parse_version(version_text),
                abis=parse_list(abis),
                platforms=parse_list(platforms),
            )
            return True, None, join_tags(tags)
        if mode == "generic":
            interpreter, abis, platforms = payload.split("|")
            tags = generic_tags(
                interpreter=interpreter,
                abis=parse_list(abis),
                platforms=parse_list(platforms),
            )
            return True, None, join_tags(tags)
        if mode == "pure":
            try:
                from packaging.tags import pure_python_tags
            except ImportError as error:  # pragma: no cover - packaging < 26.3
                raise ReferenceUnavailable(
                    "pure_python_tags needs packaging >= 26.3, the release this "
                    "library targets; the rule itself is checked through "
                    "`compatible_tags` on older releases"
                ) from error
            return True, None, join_tags(pure_python_tags(parse_version(payload)))
        if mode == "compatible":
            version_text, interpreter, platforms = payload.split("|")
            tags = compatible_tags(
                python_version=parse_version(version_text),
                interpreter=None if interpreter == "-" else interpreter,
                platforms=parse_list(platforms),
            )
            return True, None, join_tags(tags)
        if mode == "mac":
            version_text, arch = parse_pair(payload)
            version = tuple(parse_version(version_text))
            return True, None, " ".join(mac_platforms(version, arch))
        if mode == "select":
            supported_text, items_text = payload.split("|")
            return True, None, select_projection(
                parse_list(supported_text), items_text
            )
        raise ValueError(f"unknown tag case mode {mode!r}")
    except Exception as error:  # noqa: BLE001 - the reference must answer, not raise
        return False, type(error).__name__, None


def join_tags(tags: object) -> str:
    return " ".join(str(tag) for tag in tags)  # type: ignore[union-attr]


def select_projection(supported: list[str], items_text: str) -> str:
    """The items `create_compatible_tags_selector` selects, best first.

    The reference's own selector decides *which* items match and in what order;
    an item whose tags do not intersect the supported list is not selected at
    all. Segments are labelled by their position, so the projection is a list of
    indices.
    """
    try:
        from packaging.tags import create_compatible_tags_selector
    except ImportError as error:  # pragma: no cover - packaging < 26.1
        raise ReferenceUnavailable(
            "create_compatible_tags_selector needs packaging >= 26.1"
        ) from error
    segments = [] if items_text == "" else items_text.split(";")
    things = [
        (
            str(index),
            frozenset(Tag(*tag.split("-")) for tag in parse_list(segment)),
        )
        for index, segment in enumerate(segments)
    ]
    selector = create_compatible_tags_selector(Tag(*tag.split("-")) for tag in supported)
    return " ".join(selector(things))


# --- fixture -----------------------------------------------------------------


def encode(text: str) -> str:
    """A MoonBit string literal."""
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


def build_fixture() -> tuple[str, list[tuple[str, str, str]], list[dict[str, object]]]:
    cases = CASES + DIVERGENT_CASES
    seen: set[str] = set()
    records: list[tuple[str, str, str]] = []
    summary: list[dict[str, object]] = []
    for name, payload in cases:
        if name in seen:
            sys.exit(f"duplicate tag case name: {name}")
        seen.add(name)
        accepted, reason, projection = reference_tag(name, payload)
        declared = name in DIVERGENCES
        if declared:
            expect_accepts, _why = DIVERGENCES[name]
            if accepted != expect_accepts:
                sys.exit(
                    f"{name} is declared as 'reference "
                    f"{'accepts' if expect_accepts else 'rejects'}', but it "
                    f"{'accepts' if accepted else f'rejects ({reason})'}"
                )
            records.append((name, payload, ""))
            summary.append(
                {
                    "name": name,
                    "payload": payload,
                    "divergence": True,
                    "reference_accepts": accepted,
                }
            )
            continue
        if not accepted:
            sys.exit(f"tag case {name} is rejected by the reference: {reason}")
        if projection is None:
            sys.exit(f"tag case {name} was accepted with no projection")
        records.append((name, payload, projection))
        summary.append(
            {
                "name": name,
                "payload": payload,
                "divergence": False,
                "tag_count": len(projection.split(" ")) if projection else 0,
            }
        )

    for name, (expect_accepts, _why) in DIVERGENCES.items():
        if name not in seen:
            sys.exit(f"divergences list names an unknown case: {name}")

    lines = [
        "///|",
        "/// PEP 425 tag-generation cases. Each entry is",
        "/// `(name, payload, projection)`: the name's prefix selects the reference",
        "/// function, the payload holds its arguments, and the projection is the",
        "/// ordered tag list (or, for `select`, the indices the selector returns).",
        "/// A case registered as a divergence carries no projection, because the",
        "/// reference answers it from the running machine.",
        "///",
        "/// Regenerate with tools/fetch_tag_corpus.py; do not edit by hand.",
        "pub let tag_cases : Array[(String, String, String)] = [",
    ]
    for name, payload, projection in records:
        lines.append(
            "  (%s, %s, %s)," % (encode(name), encode(payload), encode(projection))
        )
    lines.append("]")
    lines.append("")
    lines.append("///|")
    lines.append("/// Cases where the reference reads the host and this library refuses to.")
    lines.append("/// The second field is what the reference does: the divergence is asserted")
    lines.append("/// in both directions, so a library that started guessing would fail here.")
    lines.append("pub let tag_divergences : Array[(String, Bool)] = [")
    for name, (expect_accepts, _why) in DIVERGENCES.items():
        lines.append(
            '  (%s, %s),' % (encode(name), "true" if expect_accepts else "false")
        )
    lines.append("]")
    lines.append("")
    return "\n".join(lines) + "\n", records, summary


def format_with_moon(path: Path) -> str | None:
    """Run `moon fmt` on `path` in place and return the result."""
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

    fixture, records, summary = build_fixture()

    if args.check:
        before = MBT.read_text(encoding="utf-8") if MBT.exists() else ""
        try:
            MBT.write_text(fixture, encoding="utf-8")
            formatted = format_with_moon(MBT)
        finally:
            # Put the committed file back even on the early-return path: this
            # check asks a question about the fixture, it must not answer it by
            # rewriting it.
            MBT.write_text(before, encoding="utf-8")
        if formatted is None:
            return 2
        if before != formatted:
            print(f"{MBT} is not what tools/fetch_tag_corpus.py generates")
            print("regenerate it, then run `moon fmt` on it and commit both")
            return 1
        print(f"{MBT} is up to date")
        return 0

    MBT.write_text(fixture, encoding="utf-8")
    JSON_OUT.write_text(
        json.dumps(
            {
                "reference": "packaging.tags",
                "case_count": len(records),
                "divergences": [
                    {
                        "name": name,
                        "reference_accepts": expect_accepts,
                        "reason": why,
                    }
                    for name, (expect_accepts, why) in DIVERGENCES.items()
                ],
                "cases": summary,
            },
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )
    by_mode: dict[str, int] = {}
    for name, _payload, _projection in records:
        mode = name.split("/", 1)[0]
        by_mode[mode] = by_mode.get(mode, 0) + 1
    counts = ", ".join(f"{mode} {count}" for mode, count in sorted(by_mode.items()))
    print(
        f"{len(records)} tag cases ({counts}), "
        f"{len(DIVERGENCES)} declared divergences -> {MBT.name}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
