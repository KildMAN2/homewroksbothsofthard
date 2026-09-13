#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULT_DIR="$ROOT_DIR/results/attempt1"
REPORT_FILE="$ROOT_DIR/reports/attempt1_results.txt"
LOG_FILE="$ROOT_DIR/logs/07_attempt1_run.log"
ENV_FILE="$RESULT_DIR/environment.txt"
PYPERF_FILE="$RESULT_DIR/attempt1.json"
PERF_DATA_FILE="$RESULT_DIR/perf.data"
PERF_STDOUT_FILE="$RESULT_DIR/perf_stdout.txt"
PERF_STDERR_FILE="$RESULT_DIR/perf_stderr.txt"
MANIFEST_FILE="$ROOT_DIR/optimized/attempt1/MANIFEST"

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
  echo "PYPERFORMANCE_VERSION=$(pyperformance --version 2>&1 || true)"
  echo "PERF_PATH=$(command -v perf || true)"
} > "$ENV_FILE"

{
  echo "COMMAND=perf record -F 999 -g -o $PERF_DATA_FILE -- python3-dbg -m pyperformance run --manifest $MANIFEST_FILE --bench raytrace_attempt1"
  echo "ENVIRONMENT_FILE=$ENV_FILE"
  echo "Original source: $ROOT_DIR/original/bm_raytrace/run_benchmark.py"
  echo "Attempt1 source: $ROOT_DIR/optimized/attempt1/run_benchmark.py"
  echo "Attempt1 manifest: $MANIFEST_FILE"
  echo "Running optimized attempt1 benchmark only; original source is untouched."
} > "$LOG_FILE"

echo "Running attempt1 command:"
echo "perf record -F 999 -g -o $PERF_DATA_FILE -- python3-dbg -m pyperformance run --manifest $MANIFEST_FILE --bench raytrace_attempt1"
echo

set +e
perf record -F 999 -g -o "$PERF_DATA_FILE" -- python3-dbg -m pyperformance run --manifest "$MANIFEST_FILE" --bench raytrace_attempt1 \
  > >(tee "$PERF_STDOUT_FILE") \
  2> >(tee "$PERF_STDERR_FILE" >&2)
STATUS=$?
set -e

{
  echo "EXIT_STATUS=$STATUS"
  echo "STDOUT_FILE=$PERF_STDOUT_FILE"
  echo "STDERR_FILE=$PERF_STDERR_FILE"
  echo "RESULT_FILE=$PERF_DATA_FILE"
  echo "PYPERF_FILE=$PYPERF_FILE"
  echo "ENV_FILE=$ENV_FILE"
} >> "$LOG_FILE"

exit $STATUS
