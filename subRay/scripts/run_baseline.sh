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
} > "$ENV_FILE"

{
  echo "COMMAND=pyperformance run --benchmarks raytrace -o $PYPERF_FILE"
  echo "ENVIRONMENT_FILE=$ENV_FILE"
  echo "Original source: $ROOT_DIR/original/bm_raytrace/run_benchmark.py"
  echo "Original metadata: $ROOT_DIR/original/bm_raytrace/pyproject.toml"
  echo "Running original benchmark only; no source modifications are performed."
} > "$LOG_FILE"

set +e
pyperformance run --benchmarks raytrace -o "$PYPERF_FILE" > "$STDOUT_FILE" 2> "$STDERR_FILE"
STATUS=$?
set -e

{
  echo "EXIT_STATUS=$STATUS"
  echo "STDOUT_FILE=$STDOUT_FILE"
  echo "STDERR_FILE=$STDERR_FILE"
  echo "RESULT_FILE=$PYPERF_FILE"
  echo "ENV_FILE=$ENV_FILE"
} >> "$LOG_FILE"

if [ -f "$PYPERF_FILE" ]; then
  cp -f "$PYPERF_FILE" "$RESULT_DIR/raytrace_result.json"
fi

exit $STATUS
