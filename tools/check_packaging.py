"""Optional independent oracle: Python packaging 26.3; not a runtime dependency.

Run: python -B tools/check_packaging.py
Requires moon and Node on PATH. Does not write fixtures or install packages.
"""
import subprocess
from pathlib import Path
import packaging
from packaging.version import Version
from packaging.specifiers import SpecifierSet

if packaging.__version__ != "26.3":
    raise SystemExit("Oracle requires packaging==26.3")
result = subprocess.run(
    ["moon", "run", "examples/oracle", "--target", "js"],
    cwd=Path(__file__).resolve().parents[1], text=True, capture_output=True,
    check=True, encoding="utf-8",
)
errors = []
count = 0
for line in result.stdout.splitlines():
    mode, left, right, actual = line.split("\t")
    if mode == "compare":
        a, b = Version(left), Version(right)
        expected = str((a > b) - (a < b))
        actual = str((int(actual) > 0) - (int(actual) < 0))
    else:
        expected = str(SpecifierSet(left).contains(
            Version(right), prereleases={"auto": None, "true": True, "false": False}[mode]
        )).lower()
    count += 1
    if actual != expected:
        errors.append(f"{mode} {left!r} {right!r}: got {actual}, expected {expected}")
print(f"packaging {packaging.__version__}: {count} comparisons, {len(errors)} mismatches")
print("\n".join(errors[:50]))
raise SystemExit(bool(errors))
