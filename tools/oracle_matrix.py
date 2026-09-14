#!/usr/bin/env python3
"""Replay one differential corpus against several PyPA ``packaging`` releases.

The library is written against a specific ``packaging`` release (26.3). This
script captures the corpus once, replays it with every interpreter you pass in
and prints a Markdown table of mismatches and tolerated policy drift, so the
version pin can be justified with data instead of a comment.

Each interpreter must already have ``packaging`` installed, for example::

    python3 -m venv /tmp/packaging-24.2 && /tmp/packaging-24.2/bin/pip install packaging==24.2

Usage::

    python -B tools/oracle_matrix.py \
        --oracle python3 \
        --oracle /tmp/packaging-24.2/bin/python \
        --oracle /tmp/packaging-25.0/bin/python \
        --oracle /tmp/packaging-26.3/bin/python \
        --report-dir build/oracle

Exit status: 0 = the pinned oracle agrees, 1 = it disagrees or no oracle ran.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tempfile
from pathlib import Path


def oracle_version(python: str) -> str:
    completed = subprocess.run(
        [python, "-c", "import packaging; print(packaging.__version__)"],
        capture_output=True,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        raise SystemExit(f"{python} has no importable packaging: {completed.stderr.strip()}")
    return completed.stdout.strip()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--oracle", action="append", default=[], help="python executable (repeatable)")
    parser.add_argument("--pinned", default="26.3", help="packaging release the library targets")
    parser.add_argument("--target", default="js", help="MoonBit backend used to capture the corpus")
    parser.add_argument("--report-dir", default=None, help="directory for per-oracle JSON reports")
    args = parser.parse_args(argv)

    root = Path(__file__).resolve().parents[1]
    harness = root / "tools" / "diff_packaging.py"
    oracles = args.oracle or [sys.executable]
    reports = Path(args.report_dir) if args.report_dir else None
    if reports:
        reports.mkdir(parents=True, exist_ok=True)

    rows = []
    pinned_mismatches = 0
    with tempfile.TemporaryDirectory() as tmp:
        corpus = Path(tmp) / "corpus.tsv"
        capture = subprocess.run(
            [
                sys.executable,
                "-B",
                str(harness),
                "--target",
                args.target,
                "--capture",
                str(corpus),
                "--capture-only",
            ],
            cwd=root,
            check=False,
        )
        if capture.returncode != 0:
            return 2

        print(f"corpus: {corpus.stat().st_size} bytes captured from target {args.target}\n")
        for python in oracles:
            version = oracle_version(python)
            report_path = reports / f"oracle-{version}.json" if reports else Path(tmp) / f"{version}.json"
            completed = subprocess.run(
                [
                    python,
                    "-B",
                    str(harness),
                    "--input",
                    str(corpus),
                    "--target",
                    args.target,
                    "--pinned-oracle",
                    args.pinned,
                    "--tolerate-drift",
                    "--json",
                    str(report_path),
                ],
                cwd=root,
                capture_output=True,
                text=True,
                check=False,
            )
            # A missing report means the sub-run never got as far as writing
            # one, which is an environment or protocol problem rather than a
            # difference between two releases. Reading the file first would turn
            # that into a bare FileNotFoundError and hide the actual message, so
            # the sub-run's output is reported before the report is read.
            if not report_path.exists():
                sys.stderr.write(completed.stderr[-4000:])
                sys.stderr.write(completed.stdout[-2000:])
                print(
                    f"oracle {version} ({python}) produced no report: "
                    f"exit {completed.returncode}",
                    file=sys.stderr,
                )
                return 2
            report = json.loads(report_path.read_text(encoding="utf-8"))
            rows.append(
                {
                    "version": version,
                    "interpreter": python,
                    "records": report["records"],
                    "differences": report["difference_total"],
                    "fatal": report["mismatch_total"],
                    "drift": report["policy_drift_total"],
                    "drift_causes": report["policy_drift_causes"],
                    "mismatch_groups": report["mismatches"],
                }
            )
            if version == args.pinned:
                pinned_mismatches = report["mismatch_total"]
            if completed.returncode == 2:
                sys.stderr.write(completed.stderr)
                return 2

    print("| packaging | records | differences | fatal | causes |")
    print("| --- | ---: | ---: | ---: | --- |")
    for row in rows:
        causes = ", ".join(f"{k} x{v}" for k, v in sorted(row["drift_causes"].items())) or "-"
        marker = " (pinned)" if row["version"] == args.pinned else ""
        print(
            f"| {row['version']}{marker} | {row['records']} | {row['differences']} | "
            f"{row['fatal']} | {causes} |"
        )
    for row in rows:
        if row["mismatch_groups"]:
            print(f"\npackaging {row['version']} mismatch groups: {json.dumps(row['mismatch_groups'], sort_keys=True)}")

    if reports:
        print(f"\nper-oracle reports written to {reports}")
    print(
        "\nDifferences on non-pinned releases are upstream behaviour changes the library "
        "documents; only the pinned release must agree."
    )
    if pinned_mismatches:
        print(f"\nFAILED: packaging {args.pinned} disagrees at {pinned_mismatches} records")
        return 1
    print(f"\nOK: packaging {args.pinned} agrees with the library on the whole corpus")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
