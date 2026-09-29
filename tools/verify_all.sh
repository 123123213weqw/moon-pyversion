#!/usr/bin/env bash
# The whole gate, in one command, from the repository itself.
#
# Every check this project claims to run is a step below, in the order the
# documents describe them. It lives in the repository rather than in someone's
# `/tmp` so that a reviewer can run the same thing the author ran, and so that the
# list of checks moves together with the code it checks (a step whose command line
# is wrong is a step that fails here).
#
# Usage:
#     bash tools/verify_all.sh
#
# Environment:
#     MOON     the moon executable (default: `moon`, or ~/.moon/bin/moon if present)
#     PY       python3 for the tools that need no oracle (default: `python3`)
#     ORACLE   a CPython with `packaging` 26.3 and `tomli` (default:
#              ~/oracle-versions/venv26.3/bin/python). Without it the
#              differential and fixture steps are reported as skipped and the
#              audit runs without `--require-all`, because "not checked" is a
#              different answer from "checked and failing".
#     ORACLES  space-separated interpreters for the drift matrix (default: the
#              four venv{24.2,25.0,26.0,26.3} interpreters under ~/oracle-versions)
#     WORK     where the reports are written (default: a fresh temporary tree)
#
# Exit status is 0 only when every step that ran passed; skipped steps and the
# number of failures are printed in the last line.
set -u

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

if [ -x "$HOME/.moon/bin/moon" ]; then
  PATH="$HOME/.moon/bin:$PATH"
fi
MOON=${MOON:-moon}
PY=${PY:-python3}
ORACLE=${ORACLE:-$HOME/oracle-versions/venv26.3/bin/python}
WORK=${WORK:-$(mktemp -d "${TMPDIR:-/tmp}/moon-pyversion-gate.XXXXXX")}
mkdir -p "$WORK"
if [ -z "${ORACLES:-}" ]; then
  ORACLES="$HOME/oracle-versions/venv24.2/bin/python"
  ORACLES="$ORACLES $HOME/oracle-versions/venv25.0/bin/python"
  ORACLES="$ORACLES $HOME/oracle-versions/venv26.0/bin/python"
  ORACLES="$ORACLES $HOME/oracle-versions/venv26.3/bin/python"
fi

PARITY="$WORK/parity.json"
CORPUS="$WORK/corpus.tsv"
TARGET_REPORT="$WORK/report-26.3.json"
ORACLE_REPORTS="$WORK/oracle-reports"

fail=0
skipped=0
step() { echo; echo "################ $*"; }
skip() { echo "SKIPPED: $*"; skipped=$((skipped + 1)); }

step "toolchain"
"$MOON" version --all | head -3

step "fmt --check"
"$MOON" fmt --check && echo "fmt clean" || fail=1

for t in wasm wasm-gc js native; do
  step "$t"
  "$MOON" check --target "$t" --deny-warn && echo "check ok" || fail=1
  "$MOON" build --target "$t" --deny-warn && echo "build ok" || fail=1
  "$MOON" test --target "$t" --deny-warn 2>&1 | tail -1 || fail=1
  "$MOON" run examples/basic --target "$t" >/dev/null && echo "basic ok" || fail=1
  "$MOON" run examples/metadata-check --target "$t" > "$WORK/dc-$t.txt" || fail=1
  "$MOON" run examples/resolve --target "$t" > "$WORK/cr-$t.txt" || fail=1
  "$MOON" run examples/audit --target "$t" > "$WORK/au-$t.txt" || fail=1
  "$MOON" run examples/upgrade-check --target "$t" > "$WORK/uc-$t.txt" || fail=1
done

step "scenario reports identical on the four backends"
for report in dc cr au uc; do
  cmp "$WORK/$report-wasm.txt" "$WORK/$report-wasm-gc.txt" \
    && cmp "$WORK/$report-wasm.txt" "$WORK/$report-js.txt" \
    && cmp "$WORK/$report-wasm.txt" "$WORK/$report-native.txt" \
    && echo "$report identical" || fail=1
done
md5sum "$WORK/dc-wasm.txt" "$WORK/cr-wasm.txt" "$WORK/au-wasm.txt" "$WORK/uc-wasm.txt"

step "examples/bench js"
"$MOON" run examples/bench --target js || fail=1

step "tools/source_metrics.py"
"$PY" -B tools/source_metrics.py | tail -8 || fail=1

step "tools/target_parity.py"
"$PY" -B tools/target_parity.py --json "$PARITY" || fail=1

if [ -x "$ORACLE" ]; then
  step "tools/diff_packaging.py vs packaging 26.3"
  "$ORACLE" -B tools/diff_packaging.py --oracle-version 26.3 \
    --capture "$CORPUS" --json "$TARGET_REPORT" | tail -12 || fail=1

  step "tools/oracle_matrix.py"
  matrix_args=""
  for python in $ORACLES; do
    if [ -x "$python" ]; then
      matrix_args="$matrix_args --oracle $python"
    else
      skip "no interpreter at $python, so that oracle is missing from the drift matrix"
    fi
  done
  # shellcheck disable=SC2086  # the argument list is built word by word above
  "$ORACLE" -B tools/oracle_matrix.py $matrix_args --report-dir "$ORACLE_REPORTS" || fail=1

  step "tools/mutation_probe.py"
  "$ORACLE" -B tools/mutation_probe.py --oracle "$ORACLE" || fail=1

  step "fixtures match their generators"
  # The full checks; CI cannot run the metadata one, which needs the downloaded
  # `METADATA` cache, and the cache is deliberately not committed -- CI runs
  # `--check-cases` for it instead.
  "$ORACLE" -B tools/fetch_pylock_corpus.py --check || fail=1
  "$ORACLE" -B tools/fetch_tag_corpus.py --check || fail=1
  "$ORACLE" -B tools/fetch_upgrade_corpus.py --check || fail=1
  "$ORACLE" -B tools/fetch_metadata_corpus.py --check --offline | tail -2 || fail=1

  step "corpus determinism"
  "$MOON" run examples/diff --target js | md5sum
  "$MOON" run examples/diff --target js | md5sum | tee "$WORK/md5-second-run.txt"
  md5sum "$CORPUS"
else
  skip "no oracle at $ORACLE: the differential, mutation, fixture and drift steps need one"
fi

step "tools/doc_audit.py"
# `--require-all` turns "a claim could not be checked" into exit 2. That is the
# right gate once the reports above exist; without an oracle they cannot, so the
# audit is asked the smaller question instead of being asked to pretend.
if [ -x "$ORACLE" ] && [ -d "$ORACLE_REPORTS" ] && [ -f "$TARGET_REPORT" ]; then
  "$PY" -B tools/doc_audit.py --full --require-all --require-clean --self-test \
    --parity-json "$PARITY" --oracle-reports "$ORACLE_REPORTS" \
    --target-report "$TARGET_REPORT" || fail=1
else
  skip "the audit runs without --require-all and without the oracle reports"
  "$PY" -B tools/doc_audit.py --full --require-clean --self-test \
    --parity-json "$PARITY" || fail=1
fi

step "VERDICT fail=$fail skipped=$skipped"
echo "reports in $WORK"
exit "$fail"
