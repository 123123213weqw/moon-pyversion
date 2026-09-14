"""Report auditable source-size categories without modifying the repository."""

from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def lines(path: Path) -> int:
    return len(path.read_text(encoding="utf-8").splitlines())


def records(paths: list[Path]) -> list[dict[str, int | str]]:
    return [
        {"path": path.relative_to(ROOT).as_posix(), "lines": lines(path)}
        for path in sorted(paths)
    ]


production = [
    path
    for path in ROOT.glob("*.mbt")
    if not path.name.endswith("_test.mbt") and path.name != "pkg.generated.mbti"
]
tests = list(ROOT.glob("*_test.mbt"))
examples = list((ROOT / "examples").rglob("*.mbt"))
fixtures = list((ROOT / "fixtures").rglob("*.mbt"))
tools = list((ROOT / "tools").glob("*.py"))

groups = {
    "production_moonbit": records(production),
    "test_moonbit": records(tests),
    "example_moonbit": records(examples),
    "generated_fixture_moonbit": records(fixtures),
    "verification_python": records(tools),
}
report = {
    "method": (
        "physical UTF-8 lines; root production MoonBit excludes *_test.mbt, "
        "examples, fixtures and generated interfaces"
    ),
    "groups": {
        name: {
            "files": len(items),
            "lines": sum(int(item["lines"]) for item in items),
            "detail": items,
        }
        for name, items in groups.items()
    },
}
print(json.dumps(report, ensure_ascii=False, indent=2))
