#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULT_DIR="$ROOT_DIR/results/baseline"
REPORT_FILE="$ROOT_DIR/reports/baseline_results.txt"
LOG_FILE="$ROOT_DIR/logs/03_baseline_run.log"
ENV_FILE="$RESULT_DIR/environment.txt"
STDOUT_FILE="$RESULT_DIR/stdout.txt"
STDERR_FILE="$RESULT_DIR/stderr.txt"
PYPERF_FILE="$RESULT_DIR/raytrace.json"
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
  echo "COMMAND=perf record -F 999 -g -- python3-dbg -m pyperformance run --bench raytrace"
  echo "ENVIRONMENT_FILE=$ENV_FILE"
  echo "Original source: $ROOT_DIR/original/bm_raytrace/run_benchmark.py"
  echo "Original metadata: $ROOT_DIR/original/bm_raytrace/pyproject.toml"
  echo "Running original benchmark only; no source modifications are performed."
} > "$LOG_FILE"

set +e
perf record -F 999 -g -o "$PERF_DATA_FILE" -- python3-dbg -m pyperformance run --bench raytrace > "$PERF_STDOUT_FILE" 2> "$PERF_STDERR_FILE"
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
  cp -f "$PERF_DATA_FILE" "$RESULT_DIR/raytrace_perf.data"
fi

exit $STATUS
