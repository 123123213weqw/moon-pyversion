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
        # The comparison canonicalizes the left operand too, but the left
        # operand of a set-valued clause is a literal that the parser has
        # already normalized, so removing that call alone cannot be observed.
        # What is observable is the environment half: `packaging` rewrites the
        # values it is handed, and the `oddnames` corpus environment spells its
        # extra and its set members the way a `pyproject.toml` may spell them.
        "name": "marker-extra-environment-not-normalized",
        "file": "markers.mbt",
        "old": """  match MarkerVar::parse(key) {
    Some(Extra) => self.values[key] = canonicalize_name(value)
    _ => self.values[key] = value
  }""",
        "new": """  ignore(MarkerVar::parse(key))
  self.values[key] = value""",
        "covers": "PEP 685: the environment's extra name is normalized too",
    },
    {
        "name": "marker-set-members-not-normalized",
        "file": "markers.mbt",
        "old": """  let names : Array[String] = []
  for name in value {
    names.push(canonicalize_name(name))
  }
  self.names[key] = names""",
        "new": """  self.names[key] = value""",
        "covers": "PEP 685/735: set-valued environment members are normalized too",
    },
    {
        "name": "marker-in-operand-swapped",
        "file": "markers.mbt",
        "old": """        In => text.contains(lhs)
        NotIn => !text.contains(lhs)""",
        "new": """        In => lhs.contains(text)
        NotIn => !lhs.contains(text)""",
        "covers": "`lhs in rhs` asks whether lhs occurs inside rhs",
    },
    {
        "name": "marker-vocabulary-misses-extras",
        "file": "markers.mbt",
        "old": """    "os_name", "os.name", "extras", "extra",""",
        "new": """    "os_name", "os.name", "extra",""",
        "covers": "the marker vocabulary is closed and complete",
    },
    {
        "name": "requirement-marker-not-validated",
        "file": "requirements.mbt",
        "old": "  validate_marker_text(text)",
        "new": "  ignore(text)",
        "covers": "a bad marker makes the whole requirement bad",
    },
    {
        "name": "license-lookup-case-sensitive",
        "file": "licenses.mbt",
        "old": """  for entry in table {
    if entry.0 == key {
      return Some(entry.1)
    }
  }
  None""",
        "new": """  for entry in table {
    if entry.1 == key {
      return Some(entry.1)
    }
  }
  None""",
        "covers": "SPDX identifiers are matched case-insensitively",
    },
    {
        "name": "toml-inline-table-allows-newline",
        "file": "toml.mbt",
        "old": """  if self.peek() == 10 {
    self.fail("NEWLINE_IN_INLINE_TABLE")
  }""",
        "new": """  if self.peek() == 10 {
    self.advance()
    self.skip_ws()
  }""",
        "covers": "an inline table stays on one line in TOML 1.0, and the declared leniency still diverges",
    },
    {
        "name": "toml-multiline-skips-first-character",
        "file": "toml.mbt",
        "old": """  let mut text = self.parse_basic_string(true, true)""",
        "new": """  let mut text = self.parse_basic_string(true, false)""",
        "covers": "a multiline string keeps its first character",
    },
    {
        "name": "toml-integer-narrowed-to-32-bit",
        "file": "toml.mbt",
        "old": """  let value = @string.parse_int64(digits, base~) catch {
    _ => self.fail("INTEGER_OUT_OF_RANGE")
  }""",
        "new": """  let value = Int64::from_int(@string.parse_int(digits, base~) catch {
    _ => self.fail("INTEGER_OUT_OF_RANGE")
  }) catch {
    _ => self.fail("INTEGER_OUT_OF_RANGE")
  }""",
        "covers": "TOML integers are 64-bit, not 32-bit",
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


def default_oracle() -> str:
    """The interpreter that holds the pinned oracle, when this machine has one.

    The corpus needs a TOML reference reader too, which only the pinned venv is
    guaranteed to have; falling back to `python3` would fail on Linux 3.10.
    """
    pinned = Path.home() / "oracle-versions" / "venv26.3" / "bin" / "python"
    if pinned.exists():
        return str(pinned)
    return sys.executable


def run(command: list[str], cwd: Path, env: dict) -> subprocess.CompletedProcess:
    return subprocess.run(command, cwd=cwd, capture_output=True, env=env, check=False)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--target", default="js", choices=["js", "wasm", "wasm-gc", "native"])
    parser.add_argument(
        "--oracle",
        default=None,
        help="python with packaging 26.3 installed (defaults to ~/oracle-versions/venv26.3)",
    )
    parser.add_argument("--pinned-oracle", default="26.3")
    parser.add_argument("--list", action="store_true", help="list mutations and exit")
    args = parser.parse_args(argv)

    if args.list:
        for mutation in MUTATIONS:
            print(f"{mutation['name']:<42} {mutation['file']:<14} {mutation['covers']}")
        return 0

    root = Path(__file__).resolve().parents[1]
    moon = shutil.which("moon") or str(Path.home() / ".moon" / "bin" / "moon")
    oracle = args.oracle or default_oracle()
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
                if not report_path.exists():
                    # The harness did not get far enough to write a report; that
                    # is a harness or protocol problem, not evidence of coverage.
                    print(f"{mutation['name']:<44} {'-':>10}  HARNESS ERROR")
                    sys.stderr.write(
                        completed.stderr.decode("utf-8", "replace")[-2000:]
                    )
                    sys.stderr.write(
                        completed.stdout.decode("utf-8", "replace")[-500:]
                    )
                    undetected.append(mutation["name"])
                    continue
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
