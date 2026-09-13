#!/usr/bin/env python3
"""Check that the differential harness actually detects regressions.

A green differential run only means something if the comparison can fail. This
script deliberately breaks the library in ways a real bug would look like,
re-runs the corpus, and asserts that `tools/diff_packaging.py` reports
mismatches. A mutation that stays green means the corpus does not cover that
behaviour, which is a gap in the experiment rather than a pass.

Each mutation is applied to a single source file, which is restored afterwards
even if the run fails.

Usage::

    python -B tools/mutation_probe.py
    python -B tools/mutation_probe.py --oracle /tmp/venv/bin/python --target js
    python -B tools/mutation_probe.py --list

Exit status: 0 = every mutation was detected, 1 = at least one stayed green,
2 = environment error.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

# Each mutation must be detectable by the corpus; `covers` names the behaviour
# the corpus is supposed to exercise.
MUTATIONS = [
    {
        "name": "name-normalization-drops-trailing-separator",
        "file": "utils.mbt",
        "old": """  if pending_separator {
    out.push('-')
  }
  String::from_array(out)
}""",
        "new": """  String::from_array(out)
}""",
        "covers": "canonicalize_name keeps leading and trailing separators",
    },
    {
        "name": "tag-order-uses-default-string-compare",
        "file": "utils.mbt",
        "old": "  out.sort_by(fn(a, b) { String::lexical_compare(a, b) })",
        "new": "  out.sort()",
        "covers": "wheel tags are ordered by code point, not by length",
    },
    {
        "name": "version-key-keeps-trailing-zeros",
        "file": "utils.mbt",
        "old": "        Version::to_string({ ..v, release: trim_release(v.release) })",
        "new": "        Version::to_string(v)",
        "covers": "canonicalize_version strips trailing release zeros",
    },
    {
        "name": "wheel-name-underscores-not-normalized",
        "file": "utils.mbt",
        "old": "  let name = canonicalize_name(name_part)",
        "new": "  let name = name_part.to_lower()",
        "covers": "wheel project names are canonicalized after unescaping",
    },
    {
        "name": "sdist-splits-on-first-dash",
        "file": "utils.mbt",
        "old": """  let mut cut = -1
  for i = chars.length() - 1; i >= 0; i = i - 1 {""",
        "new": """  let mut cut = -1
  for i = 0; i < chars.length(); i = i + 1 {""",
        "covers": "sdist names split on the last dash",
    },
    {
        "name": "local-segments-compared-by-length",
        "file": "version.mbt",
        "old": "      String::lexical_compare(l.text, r.text)",
        "new": "      l.text.compare(r.text)",
        "covers": "textual local segments order lexically",
    },
    {
        "name": "prerelease-policy-always-allows",
        "file": "specifier.mbt",
        "old": """  let allow_pre = prereleases.unwrap_or(true)
  if version_is_prerelease(version) && !allow_pre {
    return false
  }""",
        "new": """  ignore(prereleases)""",
        "covers": "prereleases=Some(false) excludes prerelease candidates",
    },
]


def run(command: list[str], cwd: Path, env: dict) -> subprocess.CompletedProcess:
    return subprocess.run(command, cwd=cwd, capture_output=True, env=env, check=False)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--target", default="js", choices=["js", "wasm", "wasm-gc", "native"])
    parser.add_argument("--oracle", default=None, help="python with packaging 26.3 installed")
    parser.add_argument("--pinned-oracle", default="26.3")
    parser.add_argument("--list", action="store_true", help="list mutations and exit")
    args = parser.parse_args(argv)

    if args.list:
        for mutation in MUTATIONS:
            print(f"{mutation['name']:<42} {mutation['file']:<14} {mutation['covers']}")
        return 0

    root = Path(__file__).resolve().parents[1]
    moon = shutil.which("moon") or str(Path.home() / ".moon" / "bin" / "moon")
    oracle = args.oracle or sys.executable
    env = dict(os.environ)
    env["PATH"] = f"{Path.home() / '.moon' / 'bin'}{os.pathsep}{env.get('PATH', '')}"
    harness = root / "tools" / "diff_packaging.py"

    undetected: list[str] = []
    print(f"{'mutation':<44} {'mismatches':>10}  verdict")
    with tempfile.TemporaryDirectory() as tmp:
        report_path = Path(tmp) / "report.json"
        corpus_path = Path(tmp) / "corpus.tsv"
        for mutation in MUTATIONS:
            target = root / mutation["file"]
            original = target.read_text(encoding="utf-8")
            if mutation["old"] not in original:
                print(f"{mutation['name']:<44} {'-':>10}  SKIPPED (anchor not found)")
                undetected.append(mutation["name"])
                continue
            target.write_text(original.replace(mutation["old"], mutation["new"], 1), encoding="utf-8")
            try:
                emitted = run(
                    [moon, "run", "examples/diff", "--target", args.target], root, env
                )
                corpus_path.write_bytes(emitted.stdout)
                if emitted.returncode != 0:
                    print(f"{mutation['name']:<44} {'-':>10}  BUILD FAILED (counts as detected)")
                    continue
                completed = run(
                    [
                        oracle, "-B", str(harness),
                        "--input", str(corpus_path),
                        "--target", args.target,
                        "--pinned-oracle", args.pinned_oracle,
                        "--json", str(report_path),
                    ],
                    root, env,
                )
                report = json.loads(report_path.read_text(encoding="utf-8"))
                detected = report["mismatch_total"]
            finally:
                target.write_text(original, encoding="utf-8")
            if detected > 0:
                print(f"{mutation['name']:<44} {detected:>10}  detected")
            else:
                print(f"{mutation['name']:<44} {detected:>10}  NOT DETECTED")
                undetected.append(mutation["name"])

    if undetected:
        print(f"\nFAILED: {len(undetected)} mutation(s) stayed green, so the corpus")
        print("does not cover: " + ", ".join(undetected))
        return 1
    print(f"\nOK: all {len(MUTATIONS)} mutations were detected by the corpus")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
