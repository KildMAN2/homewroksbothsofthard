#!/usr/bin/env bash
# Runs Attempt 1 through pyperformance using its own MANIFEST, under perf
# record so we capture a matching perf.data for suite-report comparisons.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULT_DIR="$ROOT_DIR/results/attempt1"
LOG_FILE="$ROOT_DIR/logs/attempt1_run.log"
STDOUT_FILE="$RESULT_DIR/stdout.txt"
STDERR_FILE="$RESULT_DIR/stderr.txt"
PERF_DATA_FILE="$RESULT_DIR/perf.data"
MANIFEST="$ROOT_DIR/optimized/attempt1/MANIFEST"

mkdir -p "$RESULT_DIR" "$ROOT_DIR/logs"

# Run from the project root so the manifest's relative metafile resolves.
cd "$ROOT_DIR"

echo "COMMAND=perf record -F 999 -g -- python3-dbg -m pyperformance run --manifest $MANIFEST --bench pyflate_attempt1" > "$LOG_FILE"

set +e
perf record -F 999 -g -o "$PERF_DATA_FILE" -- python3-dbg -m pyperformance run --manifest "$MANIFEST" --bench pyflate_attempt1 \
  > >(tee "$STDOUT_FILE") \
  2> >(tee "$STDERR_FILE" >&2)
STATUS=$?
set -e

echo "EXIT_STATUS=$STATUS" >> "$LOG_FILE"
exit $STATUS
