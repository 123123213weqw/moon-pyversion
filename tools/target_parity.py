#!/usr/bin/env python3
"""Check that every backend emits the same differential corpus.

The corpus emitter in ``examples/diff`` is meant to be deterministic: it seeds
its generator with a constant, never reads the clock, the environment or the
network, and uses only wrapping integer arithmetic. This script runs it on
every backend and compares content after normalizing the host C runtime's CRLF
to LF. Raw and normalized hashes are both reported, so a semantic difference
cannot be hidden as a platform newline difference.

Usage::

    python -B tools/target_parity.py
    python -B tools/target_parity.py --targets js native --reference js
    python -B tools/target_parity.py --json parity.json

Exit status: 0 = all backends agree, 1 = divergence, 2 = environment error.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

TARGETS = ("wasm", "wasm-gc", "js", "native")


def normalized_newlines(output: bytes) -> bytes:
    """Normalize only the standard Windows CRLF convention."""
    return output.replace(b"\r\n", b"\n")


def run_target(moon: str, root: Path, target: str) -> tuple[bytes, float]:
    env = dict(os.environ)
    env["PATH"] = f"{Path.home() / '.moon' / 'bin'}{os.pathsep}{env.get('PATH', '')}"
    command = [moon, "run", "examples/diff", "--target", target]
    started = time.time()
    completed = subprocess.run(command, cwd=root, capture_output=True, env=env, check=False)
    elapsed = time.time() - started
    if completed.returncode != 0:
        sys.stderr.write(completed.stderr.decode("utf-8", "replace"))
        raise SystemExit(f"emitter failed on target {target}")
    return completed.stdout, elapsed


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--targets", nargs="+", default=list(TARGETS), choices=list(TARGETS))
    parser.add_argument("--reference", default=None, help="target whose output is the reference")
    parser.add_argument("--moon", default=None, help="path to the moon executable")
    parser.add_argument("--json", default=None, help="write a machine readable report here")
    args = parser.parse_args(argv)

    root = Path(__file__).resolve().parents[1]
    moon = args.moon or shutil.which("moon") or str(Path.home() / ".moon" / "bin" / "moon")
    reference_target = args.reference or args.targets[0]

    raw_digests: dict[str, str] = {}
    digests: dict[str, str] = {}
    sizes: dict[str, int] = {}
    records: dict[str, int] = {}
    seconds: dict[str, float] = {}
    reference_bytes: bytes | None = None
    failed: list[str] = []

    for target in args.targets:
        output, elapsed = run_target(moon, root, target)
        normalized = normalized_newlines(output)
        raw_digests[target] = hashlib.sha256(output).hexdigest()
        digests[target] = hashlib.sha256(normalized).hexdigest()
        sizes[target] = len(output)
        records[target] = normalized.count(b"\n")
        seconds[target] = round(elapsed, 2)
        if target == reference_target:
            reference_bytes = output

    print(f"reference: {reference_target}")
    print(f"{'target':<10} {'records':>8} {'bytes':>10} {'seconds':>8}  digest")
    for target in args.targets:
        digest = digests[target]
        status = ""
        if reference_bytes is not None and target != reference_target:
            if digest == digests[reference_target]:
                if raw_digests[target] == raw_digests[reference_target]:
                    status = " byte-identical"
                else:
                    status = " content-identical (newline-normalized)"
            else:
                status = " DIFFERENT"
                failed.append(target)
        print(
            f"{target:<10} {records[target]:>8} {sizes[target]:>10} {seconds[target]:>8}  "
            f"{digest[:16]}{status}"
        )

    if args.json:
        report = {
            "reference": reference_target,
            "targets": {
                target: {
                    "records": records[target],
                    "bytes": sizes[target],
                    "seconds": seconds[target],
                    "raw_sha256": raw_digests[target],
                    "normalized_sha256": digests[target],
                    "byte_identical_to_reference": (
                        raw_digests[target] == raw_digests[reference_target]
                    ),
                    "content_identical_to_reference": (
                        digests[target] == digests[reference_target]
                    ),
                }
                for target in args.targets
            },
        }
        Path(args.json).write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print(f"report written to {args.json}")

    if failed:
        print(f"\nFAILED: {', '.join(failed)} differ(s) from {reference_target}")
        return 1
    print(
        f"\nOK: {len(args.targets)} backends emitted identical corpus content "
        "after platform newline normalization"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
