#!/usr/bin/env bash
# Runs the untouched pyflate benchmark under perf record so we get both a
# pyperformance timing and a saved perf.data for later `perf report`.
# Modeled on Project/subRay/scripts/run_baseline.sh.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULT_DIR="$ROOT_DIR/results/baseline"
REPORT_FILE="$ROOT_DIR/reports/baseline_results.txt"
LOG_FILE="$ROOT_DIR/logs/03_baseline_run.log"
ENV_FILE="$RESULT_DIR/environment.txt"
STDOUT_FILE="$RESULT_DIR/stdout.txt"
STDERR_FILE="$RESULT_DIR/stderr.txt"
PERF_DATA_FILE="$RESULT_DIR/perf.data"
PERF_STDOUT_FILE="$RESULT_DIR/perf_stdout.txt"
PERF_STDERR_FILE="$RESULT_DIR/perf_stderr.txt"

mkdir -p "$RESULT_DIR" "$ROOT_DIR/reports" "$ROOT_DIR/logs"

{
  echo "DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "HOSTNAME=$(hostname)"
  echo "PWD=$(pwd)"
  echo "UNAME=$(uname -a)"
  echo "PYTHON3_VERSION=$(python3 --version 2>&1 || true)"
  echo "PYTHON3_DBG_PATH=$(command -v python3-dbg || true)"
  if command -v python3-dbg >/dev/null 2>&1; then
    echo "PYTHON3_DBG_VERSION=$(python3-dbg --version 2>&1 || true)"
  else
    echo "PYTHON3_DBG_VERSION=NOT_AVAILABLE"
  fi
  echo "PYFORMANCE_VERSION=$(pyperformance --version 2>&1 || true)"
  echo "PERF_PATH=$(command -v perf || true)"
} > "$ENV_FILE"

{
  echo "COMMAND=perf record -F 999 -g -- python3-dbg -m pyperformance run --bench pyflate"
  echo "ENVIRONMENT_FILE=$ENV_FILE"
  echo "Original source: $ROOT_DIR/original/bm_pyflate/run_benchmark.py"
  echo "Original metadata: $ROOT_DIR/original/bm_pyflate/pyproject.toml"
  echo "Running original benchmark only; no source modifications are performed."
} > "$LOG_FILE"

echo "Running baseline command:"
echo "perf record -F 999 -g -o $PERF_DATA_FILE -- python3-dbg -m pyperformance run --bench pyflate"
echo

set +e
perf record -F 999 -g -o "$PERF_DATA_FILE" -- python3-dbg -m pyperformance run --bench pyflate \
  > >(tee "$PERF_STDOUT_FILE") \
  2> >(tee "$PERF_STDERR_FILE" >&2)
STATUS=$?
set -e

{
  echo "EXIT_STATUS=$STATUS"
  echo "STDOUT_FILE=$PERF_STDOUT_FILE"
  echo "STDERR_FILE=$PERF_STDERR_FILE"
  echo "RESULT_FILE=$PERF_DATA_FILE"
  echo "ENV_FILE=$ENV_FILE"
} >> "$LOG_FILE"

if [ -f "$PERF_DATA_FILE" ]; then
  cp -f "$PERF_DATA_FILE" "$RESULT_DIR/pyflate_perf.data"
fi

# Copy pyperformance stdout as the baseline summary (mean/stddev line).
if [ -f "$PERF_STDOUT_FILE" ]; then
  cp -f "$PERF_STDOUT_FILE" "$STDOUT_FILE"
fi
if [ -f "$PERF_STDERR_FILE" ]; then
  cp -f "$PERF_STDERR_FILE" "$STDERR_FILE"
fi

{
  echo "Pyflate baseline"
  echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "Command: perf record -F 999 -g -o $PERF_DATA_FILE -- python3-dbg -m pyperformance run --bench pyflate"
  echo "Exit status: $STATUS"
  echo "stdout: $STDOUT_FILE"
  echo "stderr: $STDERR_FILE"
} > "$REPORT_FILE"

exit $STATUS
