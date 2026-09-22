#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROF_DIR="$ROOT_DIR/profiling"
DATA_DIR="$PROF_DIR/flamegraph_data"
LOG_DIR="$ROOT_DIR/logs"

mkdir -p "$DATA_DIR" "$LOG_DIR"

STEP_LOG="$LOG_DIR/04_flamegraph_step.txt"
SCRIPT_ERR="$LOG_DIR/04_flamegraph_perf_script_stderr.txt"
COLLAPSE_ERR="$LOG_DIR/04_flamegraph_stackcollapse_stderr.txt"
RENDER_ERR="$LOG_DIR/04_flamegraph_render_stderr.txt"

{
  echo "DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "PWD=$(pwd)"
  echo "COMMAND_1=/usr/bin/perf script -i $PROF_DIR/perf.data > $DATA_DIR/out.perf"
  echo "COMMAND_2=/opt/FlameGraph/stackcollapse-perf.pl $DATA_DIR/out.perf > $DATA_DIR/out.folded"
  echo "COMMAND_3=/opt/FlameGraph/flamegraph.pl $DATA_DIR/out.folded > $PROF_DIR/flamegraph.svg"
} > "$STEP_LOG"

cd "$PROF_DIR"

/usr/bin/perf script -i perf.data > flamegraph_data/out.perf 2> "$SCRIPT_ERR"
/opt/FlameGraph/stackcollapse-perf.pl flamegraph_data/out.perf > flamegraph_data/out.folded 2> "$COLLAPSE_ERR"
/opt/FlameGraph/flamegraph.pl flamegraph_data/out.folded > flamegraph.svg 2> "$RENDER_ERR"

{
  echo "OUT_PERF_BYTES=$(wc -c < flamegraph_data/out.perf)"
  echo "OUT_FOLDED_BYTES=$(wc -c < flamegraph_data/out.folded)"
  echo "FLAMEGRAPH_BYTES=$(wc -c < flamegraph.svg)"
} >> "$STEP_LOG"