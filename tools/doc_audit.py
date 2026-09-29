#!/usr/bin/env python3
"""Check the numbers the documents state against the tree they describe.

This repository has one recurring defect, and it is not in the library: a number
in a document goes stale while the tree moves on. It has happened to the mutation
counts, the corpus size, the drift matrix, the per-module line counts and the
package README, and every time the fix was manual. Writing the fix down is not
enough, because the next change moves the same numbers again.

So the claims are checked. This script measures what can be measured -- line
counts, test blocks, mutations, the emitted corpus, the four scenario reports,
and the artifacts of the differential runs -- and then asserts two things:

* **every stated number equals the measured one.** Each claim is a regular
  expression with one capture group per number, anchored on the sentence that
  carries it, so the check is "the document says 122 640 *here*" rather than "the
  document mentions 122 640 somewhere". A sentence that disappears is reported,
  because then the claim is no longer stated anywhere; edit this file's pattern
  when the sentence is rewritten on purpose.
* **no stale number survives.** A list of literal values that were correct once
  and are not any more must not appear in any current-state document. The check
  matches whole numbers (a digit on either side disqualifies a match, so a checksum
  cannot trip it) and skips `CHANGELOG.md`, which quotes whatever was true when
  each entry was written. A line that carries the marker `doc-audit: history` is
  skipped too: a document may explain what the numbers used to be, and that is a
  statement about the past rather than a claim about the tree. The marker is
  deliberately explicit -- it shows up in the diff, so a reviewer sees when a
  sentence stops being checked.

Numbers are compared after deleting thousands separators and the spaces inside
numeral groups, so `122,640` and `122 640` match the same fact. Nothing here
rewrites a document: a stale sentence is reported and a human rephrases it.

`--self-test` closes the obvious hole. A checker that reports `0 mismatch` is only
worth reading if it can report something else, so every claim's own sentence is
damaged on purpose -- the number changed, the sentence deleted, the fact withheld
-- and the damage has to be named. The same is done to the document-level rules,
including the two exemptions they rely on.

Usage::

    python -B tools/doc_audit.py                      # tree-only facts
    python -B tools/doc_audit.py --full               # also run moon (corpus + scenarios)
    python -B tools/doc_audit.py --full --require-all \
        --parity-json /tmp/parity.json --oracle-reports /tmp/oracle-reports \
        --target-report /tmp/report-26.3.json
    python -B tools/doc_audit.py --full --self-test   # and prove the checks can fail

A tree whose measured sources are modified is reported as a note by default --
someone who has just edited a source is exactly who needs to know which documents
went stale -- and as a failure under `--require-clean`, which is what the gate and
CI pass. The audit also hashes every measured source before and after the run and
fails if it changed while it was measuring. That is not hypothetical: a mutation
probe running in another shell edited a source mid-run, and the audit's first
reaction was to report the *documents* as stale.

Exit status: 0 = every claim holds, 1 = at least one mismatch, 2 = a claim the
caller required could not be checked at all.
"""

from __future__ import annotations

import argparse
import ast
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from source_metrics import measure  # noqa: E402  (local tool, same directory)

ROOT = Path(__file__).resolve().parents[1]

# Documents that state what the tree is *now*. A number that is no longer true
# must not appear in any of them.
CURRENT_DOCUMENTS = [
    "README.md",
    "README.mbt.md",
    "docs/proposal.md",
    "docs/test-report.md",
    "docs/experiment.md",
    "docs/experiment-results.md",
    "docs/design.md",
    "docs/audit-scenario.md",
    "docs/upgrade-scenario.md",
    "docs/release-verification.md",
    "docs/applicant-notes.md",
    "docs/resubmission-note.md",
    "docs/submission-checklist.md",
    "docs/provenance.md",
    "docs/plan.md",
    "docs/roadmap.md",
]

# Values that were correct at some point and are not any more. `CHANGELOG.md` is
# deliberately not searched: it records what was true when each entry was
# written, and quoting an old number there is the point of that file. The same
# goes for the defect history in `docs/experiment-results.md` section 5, which is
# why its historical spellings (122 521, 43 573) are not listed here.
STALE_VALUES = {
    "122589": "corpus size before the upgrade corpus",
    "122590": "corpus line count before the upgrade corpus",
    # 122 516 and 43 573 are deliberately absent: the defect history in
    # `docs/experiment-results.md` section 5 quotes them as history, which is the
    # same reason `CHANGELOG.md` is exempt.
    "99020": "corpus size after the PyPI metadata milestone",
    "9494": "root production MoonBit before the tag and upgrade milestones",
    "6976": "test MoonBit before the tag and upgrade milestones",
    "2109": "drift against packaging 24.2 before the tag corpus",
    "4474": "drift against packaging 24.2 before the upgrade corpus",
    "2736": "drift against packaging 25.0 before the upgrade corpus",
    "4492": "drift against packaging 24.2 before the upgrade records were counted",
    "2754": "drift against packaging 25.0 before the upgrade records were counted",
}
STALE_PHRASES = {
    "277 个测试块": "test block count before the upgrade milestone",
    "277 个块": "test block count before the upgrade milestone",
    "41 处": "mutation count before the upgrade milestone",
    "41/41": "mutation count before the upgrade milestone",
    "df7cd80290cfd38d": "corpus digest before the upgrade corpus",
    "b9d0df199cfe94cd": "corpus md5 before the tag milestone",
}

SCENARIOS = ("metadata-check", "resolve", "audit", "upgrade-check")


def normalise(text: str) -> str:
    """Drop thousands separators, but never the gaps between table columns.

    `122,640` and `122 640` are the same number; `122641   12431239` in a table is
    two numbers, and collapsing the gap there would hide exactly the kind of
    mistake this script exists to catch.
    """
    text = re.sub(r"(?<=\d)[,\u2009\u00a0]+(?=\d)", "", text)
    return re.sub(r"(?<=\d) (?=\d{3}(?!\d))", "", text)


HISTORY_MARKER = "doc-audit: history"


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def without_history_lines(text: str) -> str:
    """Drop the lines a document marks as being about the past on purpose."""
    return "\n".join(
        line for line in text.splitlines() if HISTORY_MARKER not in line
    )


MEASURED_GLOBS = ("*.mbt", "fixtures/*.mbt", "examples/**/*.mbt", "tools/*.py")


def measured_sources() -> list[Path]:
    """The files whose contents the measurements are a function of."""
    seen: dict[str, Path] = {}
    for pattern in MEASURED_GLOBS:
        for path in ROOT.glob(pattern):
            seen[path.relative_to(ROOT).as_posix()] = path
    return [seen[key] for key in sorted(seen)]


def source_digest() -> str:
    """One hash over every measured source, to detect a tree that moves."""
    digest = hashlib.md5()
    for path in measured_sources():
        digest.update(path.relative_to(ROOT).as_posix().encode("utf-8"))
        digest.update(hashlib.md5(path.read_bytes()).digest())
    return digest.hexdigest()


def dirty_sources() -> list[str]:
    """Tracked measured sources with uncommitted changes, via git if available."""
    result = subprocess.run(
        ["git", "status", "--porcelain", "--", *MEASURED_GLOBS],
        cwd=ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    if result.returncode != 0:
        return []
    dirty = []
    for line in result.stdout.decode("utf-8", "replace").splitlines():
        status, _, name = line[:2], line[2:4], line[3:]
        if status.strip() and not status.startswith("??"):
            dirty.append(name.strip())
    return dirty


def count_test_blocks() -> int:
    return sum(
        len(re.findall(r'^test "', path.read_text(encoding="utf-8"), re.M))
        for path in ROOT.glob("*_test.mbt")
    )


def count_mutations() -> int:
    tree = ast.parse((ROOT / "tools/mutation_probe.py").read_text(encoding="utf-8"))
    for node in tree.body:
        if isinstance(node, ast.Assign):
            for target in node.targets:
                if isinstance(target, ast.Name) and target.id == "MUTATIONS":
                    if not isinstance(node.value, ast.List):
                        raise SystemExit("MUTATIONS is not a list literal")
                    return len(node.value.elts)
    raise SystemExit("MUTATIONS not found in tools/mutation_probe.py")


class MoonUnavailable(RuntimeError):
    """`moon` could not be run, so the claims that need it stay unchecked."""


def run_moon(project: str, moon: str) -> bytes:
    try:
        result = subprocess.run(
            [moon, "run", project, "--target", "js"],
            cwd=ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
    except FileNotFoundError as error:
        raise MoonUnavailable(f"{moon} is not executable: {error}") from error
    if result.returncode != 0:
        raise MoonUnavailable(
            f"moon run {project} --target js failed:\n"
            + result.stderr.decode("utf-8", "replace")[-2000:]
        )
    return result.stdout


class Audit:
    def __init__(self) -> None:
        self.rows: list[tuple[str, str, str]] = []

    def claim(self, label: str, ok: bool, detail: str) -> None:
        self.rows.append((label, "ok" if ok else "MISMATCH", detail))

    def unchecked(self, label: str, detail: str) -> None:
        self.rows.append((label, "NOT CHECKED", detail))

    def note(self, label: str, detail: str) -> None:
        """Something the reader should know that is neither a pass nor a failure."""
        self.rows.append((label, "note", detail))

    def report(self, require_all: bool) -> int:
        width = max(len(label) for label, _, _ in self.rows)
        mismatches = sum(status == "MISMATCH" for _, status, _ in self.rows)
        unchecked = sum(status == "NOT CHECKED" for _, status, _ in self.rows)
        notes = sum(status == "note" for _, status, _ in self.rows)
        for label, status, detail in self.rows:
            print(f"{label.ljust(width)}  {status:<12} {detail}")
        print()
        summary = (
            f"{len(self.rows)} claim(s): {mismatches} mismatch, {unchecked} not checked"
        )
        if notes:
            summary += f", {notes} note(s)"
        summary += f" ({len(CLAIMS)} of them are assertions about the documents)"
        print(summary)
        if mismatches:
            return 1
        if unchecked and require_all:
            return 2
        return 0


# Each claim: (label suffix, document, pattern with one group per number,
# fact keys in group order). A fact whose value is `None` means "not measured in
# this run", and the claim is reported as not checked instead of failing.
CLAIMS: list[tuple[str, str, str, tuple[str, ...]]] = [
    # docs/proposal.md -- the summary table and the implementation paragraph.
    ("production lines and files", "docs/proposal.md",
     r"生产代码 ([\d, ]+) 行，分 (\d+) 个文件", ("production_lines", "production_files")),
    ("test lines and blocks", "docs/proposal.md",
     r"另有测试 ([\d, ]+) 行（(\d+) 个块）", ("test_lines", "test_blocks")),
    ("example lines and programs", "docs/proposal.md",
     r"示例 ([\d, ]+) 行（(\d+) 个程序）", ("example_lines", "example_files")),
    ("fixture lines", "docs/proposal.md", r"生成语料 ([\d, ]+) 行", ("fixture_lines",)),
    ("records", "docs/proposal.md", r"差分实验 \| ([\d, ]+) 条记录", ("records",)),
    ("test blocks", "docs/proposal.md", r"单元与属性测试 \| (\d+) 个块", ("test_blocks",)),
    ("mutations", "docs/proposal.md", r"变异探针 \| (\d+) 处故意缺陷", ("mutations",)),
    ("document claims", "docs/proposal.md",
     r"文档数字审计 \| (\d+) 条文档断言 \|", ("document_claims",)),
    ("drift", "docs/proposal.md",
     r"24\.2 差 ([\d, ]+)、25\.0 差 ([\d, ]+)、26\.0 差 ([\d, ]+)、26\.3 差 (\d+)",
     ("drift_24.2", "drift_25.0", "drift_26.0", "drift_26.3")),
    # docs/test-report.md
    ("test blocks", "docs/test-report.md", r"核心路径有 \*\*(\d+) 个测试块\*\*", ("test_blocks",)),
    ("fixture files", "docs/test-report.md",
     r"fixture 是否等于生成器当前的输出 \| (\d+) 份 fixture", ("fixture_files",)),
    # The number of claims is itself a claim: the documents say how much is
    # checked, and that sentence would otherwise be the first thing to go stale.
    # The size of the check is itself a claim. It is the number of claims *about
    # the documents*, not the number of rows in the report: the row count depends
    # on which reports were passed in, and a number that changes with the
    # invocation would be checked against the wrong thing.
    ("document claims", "docs/test-report.md",
     r"每个数字是否等于实测值 \| (\d+) 条文档断言 \|", ("document_claims",)),
    ("document claims (conclusion)", "docs/test-report.md",
     r"\| 文档数字审计 \| (\d+) 条文档断言全部成立", ("document_claims",)),
    ("document claims", "docs/experiment-results.md",
     r"`python -B tools/doc_audit\.py --full --require-all` \| (\d+) 条文档断言全部成立",
     ("document_claims",)),
    ("records", "docs/test-report.md", r"另有 \*\*([\d, ]+) 条\*\*确定性差分记录", ("records",)),
    ("mutations", "docs/test-report.md",
     r"用 \*\*(\d+) 处故意注入的缺陷\*\*", ("mutations",)),
    ("scenario md5s", "docs/test-report.md",
     r"`examples/metadata-check` md5 `([0-9a-f]{32})`、\s*"
     r"`examples/resolve` md5 `([0-9a-f]{32})`、\s*"
     r"`examples/audit` md5 `([0-9a-f]{32})`、\s*"
     r"`examples/upgrade-check` md5 `([0-9a-f]{32})`",
     ("scenario_md5.metadata-check", "scenario_md5.resolve",
      "scenario_md5.audit", "scenario_md5.upgrade-check")),
    # docs/experiment-results.md
    ("records (report)", "docs/experiment-results.md", r"records: (\d+) \(", ("records",)),
    ("records (verdict)", "docs/experiment-results.md",
     r"OK: (\d+) records agree", ("records",)),
    ("drift against 24.2", "docs/experiment-results.md",
     r"\| 24\.2 \| \d+ \| (\d+) \| \d+ \|", ("drift_24.2",)),
    ("drift against 25.0", "docs/experiment-results.md",
     r"\| 25\.0 \| \d+ \| (\d+) \| \d+ \|", ("drift_25.0",)),
    ("drift against 26.0", "docs/experiment-results.md",
     r"\| 26\.0 \| \d+ \| (\d+) \| \d+ \|", ("drift_26.0",)),
    ("corpus size in lines", "docs/experiment-results.md",
     r"条记录 / ([\d, ]+) 行语料", ("corpus_lines",)),
    ("prerelease records", "docs/experiment-results.md",
     r"其中 \*\*([\d, ]+)\*\* 条带显式预发布模式", ("prerelease_records",)),
    ("corpus md5", "docs/experiment-results.md", r"md5 一致（`([0-9a-f]{32})`）", ("corpus_md5",)),
    ("backend digest", "docs/experiment-results.md",
     r"wasm\s+(\d+)\s+(\d+)\s+[\d.]+\s+([0-9a-f]{16})",
     ("corpus_lines", "corpus_bytes", "parity_digest")),
    ("upgrade scenario md5", "docs/experiment-results.md",
     r"（md5 `([0-9a-f]{32})`）。", ("scenario_md5.upgrade-check",)),
    # docs/experiment.md
    ("record kinds", "docs/experiment.md", r"## 记录类型（(\d+) 种）", ("record_kinds",)),
    ("assertion kinds", "docs/experiment.md", r"其中 \*\*(\d+) 种是断言\*\*", ("assertion_kinds",)),
    # docs/plan.md and docs/roadmap.md
    ("production and test lines", "docs/plan.md",
     r"根目录生产 MoonBit \*\*([\d, ]+) 行\*\*、测试 \*\*([\d, ]+) 行\*\*（(\d+) 个测试块）",
     ("production_lines", "test_lines", "test_blocks")),
    ("records and mutations", "docs/plan.md",
     r"差分语料 \*\*([\d, ]+) 条\*\*.*?变异探针 \*\*(\d+) 处\*\*",
     ("records", "mutations")),
    ("production and test lines", "docs/roadmap.md",
     r"根目录生产 MoonBit 合计 \*\*([\d, ]+) 行\*\*.*?测试 \*\*([\d, ]+) 行\*\*",
     ("production_lines", "test_lines")),
    # docs/applicant-notes.md and docs/resubmission-note.md
    ("test blocks", "docs/applicant-notes.md", r"(\d+) 个 MoonBit 测试块", ("test_blocks",)),
    ("records", "docs/applicant-notes.md", r"([\d, ]+) 条记录对照", ("records",)),
    ("mutations", "docs/applicant-notes.md", r"变异探针 (\d+) 处全部检出", ("mutations",)),
    ("lines and blocks", "docs/resubmission-note.md",
     r"生产 MoonBit 为 ([\d, ]+) 行；另有\s*> ([\d, ]+) 行 MoonBit 测试、(\d+) 个测试块",
     ("production_lines", "test_lines", "test_blocks")),
    ("records and mutations", "docs/resubmission-note.md",
     r"真实语料差分共 ([\d, ]+) 条.*?mutation probe（(\d+) 处注入缺陷全部检出）",
     ("records", "mutations")),
    ("diff example lines", "docs/roadmap.md",
     r"示例 ([\d, ]+)（`diff`）", ("example_diff_lines",)),
    # The line total of the tools is deliberately *not* stated in the documents
    # and not checked here: every new tool moves it, and a number that has to be
    # updated by every unrelated change is a number nobody trusts.
    ("tool scripts", "docs/roadmap.md",
     r"工具链 (\d+) 个 Python\s*脚本", ("tool_files",)),
    # README.md and README.mbt.md
    ("records", "README.md", r"生成 \*\*([\d, ]+) 条\*\*确定性记录", ("records",)),
    ("mutations", "README.md", r"注入 (\d+) 处\*\*故意缺陷\*\*", ("mutations",)),
    ("records and kinds", "README.mbt.md",
     r"corpus of \*\*([\d, ]+) records\*\* in (\d+) kinds", ("records", "record_kinds")),
    ("mutations", "README.mbt.md", r"all (\d+) injected defects are detected", ("mutations",)),
]


def document_texts() -> dict[str, str]:
    """Every document this audit reads, straight from the tree."""
    paths = sorted({claim[1] for claim in CLAIMS} | set(CURRENT_DOCUMENTS))
    return {path: read(path) for path in paths}


def stale_scan(documents: dict[str, str]) -> dict[str, list[str]]:
    """The stale values that a current-state document still states."""
    stale: dict[str, list[str]] = {}
    for path in CURRENT_DOCUMENTS:
        raw = documents[path] if path in documents else read(path)
        text = normalise(without_history_lines(raw))
        hits = [
            f"{value} ({why})"
            for value, why in STALE_VALUES.items()
            if re.search(rf"(?<!\d){value}(?!\d)", text)
        ]
        hits += [f"{phrase} ({why})" for phrase, why in STALE_PHRASES.items() if phrase in text]
        if hits:
            stale[path] = hits
    return stale


def check_claims(
    audit: Audit,
    facts: dict[str, str | None],
    documents: dict[str, str] | None = None,
) -> None:
    """Check every claim in `CLAIMS` against the facts measured from the tree.

    `documents` replaces what would be read from disk. `--self-test` uses exactly
    that to put a damaged copy of a document in front of the same checker and
    require the damage to be reported.
    """
    if documents is None:
        documents = document_texts()
    by_file: dict[str, str] = {}
    for label, path, pattern, keys in CLAIMS:
        if path not in by_file:
            by_file[path] = normalise(documents[path])
        text = by_file[path]
        match = re.search(pattern, text, re.S)
        if match is None:
            audit.claim(f"{path}: {label}", False,
                        f"the sentence that carries this number is gone (pattern {pattern!r})")
            continue
        groups = match.groups()
        unmeasured = [k for k, g in zip(keys, groups) if facts.get(k) is None]
        if unmeasured:
            audit.unchecked(f"{path}: {label}", "not measured: " + ", ".join(unmeasured))
            continue
        stated = [g.replace(",", "").replace(" ", "") for g in groups]
        expected = [str(facts[k]) for k in keys]
        audit.claim(
            f"{path}: {label}",
            stated == expected,
            f"document says {' / '.join(stated)}, tree says {' / '.join(expected)}",
        )

    stale = stale_scan(documents)
    audit.claim(
        "no stale number in any current-state document",
        not stale,
        "; ".join(f"{path}: {', '.join(hits)}" for path, hits in stale.items()) or "none",
    )


STALE_ROW = "no stale number in any current-state document"


def status_of(facts: dict[str, str | None], documents: dict[str, str], row: str) -> str:
    """The status `check_claims` gives one claim, for one set of documents."""
    pressed = Audit()
    check_claims(pressed, facts, documents)
    for label, status, _ in pressed.rows:
        if label == row:
            return status
    return "absent"


def corrupt_number(group: str) -> str | None:
    """`122 640` -> `122 641`, leaving the separators where they were.

    `None` when the group is not a number at all: a case that cannot be built is
    not a case that passed, and the caller says so instead of counting it.
    """
    digits = re.sub(r"[,\u2009\u00a0 ]", "", group)
    if not digits.isdigit():
        return None
    bumped = str((int(digits) + 1) % 10 ** len(digits)).zfill(len(digits))
    out: list[str] = []
    seen = 0
    for char in group:
        if char.isdigit():
            out.append(bumped[seen])
            seen += 1
        else:
            out.append(char)
    return "".join(out)


def corrupt_value(group: str) -> str | None:
    """A different spelling of the same kind of value, or `None`.

    Counts and versions are bumped; a digest gets a different first digit, which
    is what makes the md5 claims -- the ones with no number to change -- take part
    in the self-test at all.
    """
    number = corrupt_number(group)
    if number is not None:
        return number
    if re.fullmatch(r"\d+(?:\.\d+)+", group):
        head, _, tail = group.rpartition(".")
        return f"{head}.{int(tail) + 1}"
    if re.fullmatch(r"[0-9a-fA-F]{8,}", group):
        return ("1" if group[0] != "1" else "0") + group[1:]
    return None


def run_self_test(audit: Audit, facts: dict[str, str | None], strict: bool) -> None:
    """Damage each claim's own sentence, and require the damage to be reported.

    `0 mismatch` is only worth reading if a mismatch is possible, so the claims
    are re-checked against overlays of their own documents: the number the claim
    states changed, the sentence that carries it deleted, and the fact it depends
    on withheld -- which has to come out as *not checked*, never as a pass. The
    document-level rules get the same treatment: a value that is no longer true
    has to be reported when a document states it, the very same value behind the
    `doc-audit: history` marker must not be, and a digit glued to either side must
    not trip the whole-number rule.

    Every case is derived from `CLAIMS`, `STALE_VALUES` and `STALE_PHRASES`, so a
    claim or a banned value added tomorrow is covered without touching this
    function.
    """
    documents = document_texts()
    failures: list[str] = []
    skipped: list[str] = []
    counts = {"changed value": 0, "withheld fact": 0, "deleted sentence": 0}
    stale_cases = {"banned value": 0, "history marker": 0, "glued digit": 0}

    def demand(
        row: str,
        case: str,
        expected: str,
        damaged: dict[str, str],
        facts_for_case: dict[str, str | None],
    ) -> int:
        """1 when the case came out as required, 0 and a failure when it did not."""
        status = status_of(facts_for_case, damaged, row)
        if status == expected:
            return 1
        failures.append(f"{row}: {case} came out as {status}, wanted {expected}")
        return 0

    for label, path, pattern, keys in CLAIMS:
        row = f"{path}: {label}"
        if any(facts.get(key) is None for key in keys):
            # A fact this run did not measure cannot be damaged either: the claim
            # is already reported as not checked by `check_claims`.
            skipped.append(row)
            continue
        text = normalise(documents[path])
        match = re.search(pattern, text, re.S)
        if match is None:
            failures.append(f"{row}: its own document no longer carries its own sentence")
            continue
        if not demand(row, "the sentence as written", "ok", documents, facts):
            continue
        for index, key in enumerate(keys, start=1):
            replaced = corrupt_value(match.group(index))
            if replaced is not None:
                changed = dict(documents)
                changed[path] = text[: match.start(index)] + replaced + text[match.end(index) :]
                counts["changed value"] += demand(
                    row, f"the value in group {index} changed", "MISMATCH", changed, facts
                )
            if facts.get(key) is not None:
                withheld = dict(facts)
                withheld[key] = None
                counts["withheld fact"] += demand(
                    row, f"the fact {key} withheld", "NOT CHECKED", documents, withheld
                )
        deleted = dict(documents)
        deleted[path] = text[: match.start()] + "（这句话已经被删掉。）" + text[match.end() :]
        counts["deleted sentence"] += demand(row, "the sentence deleted", "MISMATCH",
                                            deleted, facts)

    probe = "docs/design.md"
    if not demand(STALE_ROW, "the documents as written", "ok", documents, facts):
        return
    for value in STALE_VALUES:
        for case, suffix, expected, key in (
            ("banned value", f"\n{value}\n", "MISMATCH", "banned value"),
            ("history marker", f"\n{value}  <!-- {HISTORY_MARKER} -->\n", "ok", "history marker"),
            ("glued digit", f"\n9{value}0\n", "ok", "glued digit"),
        ):
            damaged = dict(documents)
            damaged[probe] = documents[probe] + suffix
            stale_cases[key] += demand(STALE_ROW, f"{case} {value}", expected, damaged, facts)
    for phrase in STALE_PHRASES:
        damaged = dict(documents)
        damaged[probe] = documents[probe] + f"\n{phrase}\n"
        stale_cases["banned value"] += demand(STALE_ROW, f"banned phrase {phrase}",
                                              "MISMATCH", damaged, facts)

    cases = sum(counts.values()) + sum(stale_cases.values())
    covered = f"{len(CLAIMS) - len(skipped)} of {len(CLAIMS)} claim(s)"
    if failures:
        detail = f"{len(failures)} of {cases} case(s) were not reported: " + "; ".join(failures[:4])
    else:
        detail = (
            f"{cases} case(s) over {covered}: {counts['changed value']} changed value(s), "
            f"{counts['withheld fact']} withheld fact(s), "
            f"{counts['deleted sentence']} deleted sentence(s), "
            f"{stale_cases['banned value']} banned value(s), "
            f"{stale_cases['history marker']} history-marked line(s), "
            f"{stale_cases['glued digit']} glued digit(s) -- every one was reported"
        )
    label = "self-test: a damaged document is reported"
    if skipped and strict:
        audit.unchecked(label, "not checked for " + ", ".join(skipped[:3]))
    else:
        if skipped:
            detail += f" ({len(skipped)} claim(s) skipped: their facts were not measured)"
        audit.claim(label, not failures, detail)


def derive_facts(audit: Audit, args: argparse.Namespace) -> dict[str, str | None]:
    facts: dict[str, str | None] = {}
    metrics = measure()["groups"]
    facts["production_lines"] = str(metrics["production_moonbit"]["lines"])
    facts["test_lines"] = str(metrics["test_moonbit"]["lines"])
    facts["example_lines"] = str(metrics["example_moonbit"]["lines"])
    facts["fixture_lines"] = str(metrics["generated_fixture_moonbit"]["lines"])
    facts["fixture_files"] = str(metrics["generated_fixture_moonbit"]["files"])
    facts["production_files"] = str(metrics["production_moonbit"]["files"])
    facts["example_files"] = str(metrics["example_moonbit"]["files"])
    facts["tool_lines"] = str(metrics["verification_python"]["lines"])
    facts["tool_files"] = str(metrics["verification_python"]["files"])
    facts["example_diff_lines"] = str(
        len((ROOT / "examples/diff/main.mbt").read_text(encoding="utf-8").splitlines())
    )
    facts["test_blocks"] = str(count_test_blocks())
    facts["mutations"] = str(count_mutations())
    audit.claim(
        "tree: layout",
        True,
        f"production {facts['production_lines']} lines / {metrics['production_moonbit']['files']} files, "
        f"tests {facts['test_lines']} lines / {facts['test_blocks']} blocks, "
        f"examples {facts['example_lines']}, fixtures {facts['fixture_lines']}, "
        f"tools {facts['tool_lines']} lines / {metrics['verification_python']['files']} scripts, "
        f"mutations {facts['mutations']}",
    )
    for key in ("records", "record_kinds", "assertion_kinds", "corpus_md5", "corpus_lines",
                "corpus_bytes", "parity_digest", "drift_24.2", "drift_25.0", "drift_26.0",
                "drift_26.3"):
        facts[key] = None
    for name in SCENARIOS:
        facts[f"scenario_md5.{name}"] = None

    if args.full:
        try:
            corpus = run_moon("examples/diff", args.moon)
        except MoonUnavailable as error:
            audit.unchecked("corpus + scenarios", str(error))
            corpus = None
        if corpus is not None:
            records = [line for line in corpus.split(b"\n") if line.strip()]
            kinds = {
                line.split(b"\t", 2)[1].decode("utf-8")
                for line in records
                if b"\t" in line
            }
            # The emitter ends with a blank line, so the line count is one more
            # than the record count; both are quoted in the documents and they are
            # not the same number.
            facts["records"] = str(len(records))
            facts["corpus_lines"] = str(corpus.count(b"\n"))
            facts["corpus_bytes"] = str(len(corpus))
            facts["record_kinds"] = str(len(kinds))
            facts["assertion_kinds"] = str(len(kinds) - len(INPUT_ONLY_KINDS))
            facts["corpus_md5"] = hashlib.md5(corpus).hexdigest()
            missing = sorted(INPUT_ONLY_KINDS - kinds)
            audit.claim(
                "corpus: emitted",
                not missing,
                f"{facts['records']} records, {facts['corpus_lines']} lines, "
                f"{facts['corpus_bytes']} bytes, {facts['record_kinds']} kinds "
                f"({facts['assertion_kinds']} assertions), md5 {facts['corpus_md5']}"
                + (f"; missing kinds {missing}" if missing else ""),
            )
            emitted: list[str] = []
            for name in SCENARIOS:
                try:
                    output = run_moon(f"examples/{name}", args.moon)
                except MoonUnavailable as error:
                    audit.unchecked(f"scenario: {name}", str(error))
                    continue
                facts[f"scenario_md5.{name}"] = hashlib.md5(output).hexdigest()
                emitted.append(name)
            if emitted:
                audit.claim(
                    "scenarios: emitted",
                    len(emitted) == len(SCENARIOS),
                    ", ".join(
                        f"{name} {facts[f'scenario_md5.{name}'][:12]}" for name in emitted
                    ),
                )
            if args.records:
                audit.claim(
                    "corpus: record count matches --records",
                    int(args.records) == int(facts["records"]),
                    f"--records {args.records} vs emitter {facts['records']}",
                )
    else:
        audit.unchecked("corpus + scenarios", "pass --full to run them")

    if args.parity_json:
        parity = json.loads(Path(args.parity_json).read_text(encoding="utf-8"))
        digests = {e["normalized_sha256"][:16] for e in parity["targets"].values()}
        facts["parity_digest"] = sorted(digests)[0]
        audit.claim(
            "backend parity",
            len(digests) == 1 and facts["parity_digest"] is not None,
            f"{len(digests)} distinct digest(s) across {len(parity['targets'])} targets: "
            + ", ".join(sorted(digests)),
        )
    else:
        audit.unchecked("backend parity", "pass --parity-json")

    if args.oracle_reports:
        for version in ("24.2", "25.0", "26.0"):
            path = Path(args.oracle_reports) / f"oracle-{version}.json"
            if not path.exists():
                audit.unchecked(f"drift: packaging {version}", f"{path} is missing")
                continue
            data = json.loads(path.read_text(encoding="utf-8"))
            facts[f"drift_{version}"] = str(data["difference_total"])
            audit.claim(
                f"drift: packaging {version}",
                data.get("fatal_total", 0) == 0,
                f"{facts[f'drift_{version}']} difference(s), "
                f"{data.get('fatal_total', 0)} fatal",
            )
    else:
        for version in ("24.2", "25.0", "26.0"):
            audit.unchecked(f"drift: packaging {version}", "pass --oracle-reports")

    if args.target_report:
        data = json.loads(Path(args.target_report).read_text(encoding="utf-8"))
        facts["drift_26.3"] = str(data.get("difference_total", 0))
        facts["prerelease_records"] = str(data.get("records_with_prerelease_mode", 0))
        audit.claim(
            "target oracle",
            data.get("mismatch_total") == 0,
            f"packaging {data.get('oracle_version')}: {data.get('difference_total')} "
            f"difference(s) over {data.get('records')} records",
        )
        if facts["records"] is not None:
            audit.claim(
                "target oracle: record count",
                int(data.get("records", -1)) == int(facts["records"]),
                f"report {data.get('records')} vs emitter {facts['records']}",
            )
    else:
        audit.unchecked("target oracle", "pass --target-report")

    return facts


# Record kinds that are inputs or declared divergences rather than assertions.
INPUT_ONLY_KINDS = {
    "marker_env",
    "meta_divergence",
    "index_divergence",
    "tag_divergence",
    "pylock_divergence",
}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--full", action="store_true",
                        help="also run the corpus emitter and the four scenarios")
    parser.add_argument("--require-all", action="store_true",
                        help="exit 2 if any claim could not be checked")
    parser.add_argument("--parity-json", help="tools/target_parity.py --json output")
    parser.add_argument("--oracle-reports", help="directory of oracle-<version>.json reports")
    parser.add_argument("--target-report", help="diff_packaging.py --json output for 26.3")
    parser.add_argument("--records", help="cross-check the emitter's record count against this")
    parser.add_argument("--moon", default="moon", help="the moon executable to run (default: moon)")
    parser.add_argument("--require-clean", action="store_true",
                        help="refuse to measure when measured sources are modified")
    parser.add_argument("--self-test", action="store_true",
                        help="damage every claim's own sentence and require it to be reported")
    args = parser.parse_args()

    audit = Audit()
    dirty = dirty_sources()
    if dirty:
        # A clean tree is what makes a measurement reproducible, but the person who
        # just edited a source is exactly who needs to know which documents went
        # stale -- so this is a note by default, and a failure when the caller asks
        # for a gate (`--require-clean`, which the local gate and CI pass).
        detail = (
            "modified: "
            + ", ".join(dirty)
            + " -- the numbers below describe an edited library"
        )
        if args.require_clean:
            audit.claim("tree: measured sources are the committed ones", False, detail)
            return audit.report(args.require_all)
        audit.note("tree: measured sources are the committed ones", detail)
    before = source_digest()
    facts = derive_facts(audit, args)
    after = source_digest()
    audit.claim(
        "tree: did not move while being measured",
        before == after,
        f"source digest {before[:12]} -> {after[:12]}"
        + ("" if before == after else " (something else is editing the tree)"),
    )
    facts["document_claims"] = str(len(CLAIMS))
    check_claims(audit, facts)
    if args.self_test:
        run_self_test(audit, facts, args.require_all)
    return audit.report(args.require_all)


if __name__ == "__main__":
    raise SystemExit(main())
