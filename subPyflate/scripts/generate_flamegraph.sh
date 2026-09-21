#!/usr/bin/env bash
# Turn subPyflate/profiling/perf.data into flamegraph.svg using Brendan Gregg's
# FlameGraph scripts (`stackcollapse-perf.pl`, `flamegraph.pl`). Modeled on
# subRay/scripts/generate_flamegraph.sh.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE_DIR="$ROOT_DIR/profiling"
DATA_DIR="$PROFILE_DIR/flamegraph_data"

PERF_DATA_FILE="$PROFILE_DIR/perf.data"
PERF_SCRIPT_FILE="$DATA_DIR/perf_script.out"
FOLDED_FILE="$DATA_DIR/out.folded"
FLAMEGRAPH_FILE="$PROFILE_DIR/flamegraph.svg"

FLAMEGRAPH_DIR="${FLAMEGRAPH_DIR:-$HOME/FlameGraph}"

if [ ! -f "$PERF_DATA_FILE" ]; then
  echo "[flamegraph] missing $PERF_DATA_FILE (run a profiling step first)"
  exit 2
fi

if [ ! -x "$FLAMEGRAPH_DIR/stackcollapse-perf.pl" ] || [ ! -x "$FLAMEGRAPH_DIR/flamegraph.pl" ]; then
  echo "[flamegraph] FlameGraph scripts not found under $FLAMEGRAPH_DIR"
  echo "[flamegraph] git clone https://github.com/brendangregg/FlameGraph.git \"$FLAMEGRAPH_DIR\""
  exit 3
fi

mkdir -p "$DATA_DIR"

echo "[flamegraph] perf script -> $PERF_SCRIPT_FILE"
perf script -i "$PERF_DATA_FILE" > "$PERF_SCRIPT_FILE"

echo "[flamegraph] stackcollapse -> $FOLDED_FILE"
"$FLAMEGRAPH_DIR/stackcollapse-perf.pl" < "$PERF_SCRIPT_FILE" > "$FOLDED_FILE"

echo "[flamegraph] flamegraph.pl -> $FLAMEGRAPH_FILE"
"$FLAMEGRAPH_DIR/flamegraph.pl" --title "pyflate perf flamegraph" < "$FOLDED_FILE" > "$FLAMEGRAPH_FILE"

echo "[flamegraph] wrote $FLAMEGRAPH_FILE"
