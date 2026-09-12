#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
SUBNBODY=$(cd -- "$SCRIPT_DIR/.." && pwd)
BROOT=/opt/pyperformance/pyperformance/data-files/benchmarks
OUT="$SUBNBODY/results"
FLAMEGRAPH=/opt/FlameGraph
FREQUENCY=499

mkdir -p "$OUT"

rm -f \
    "$OUT/perf_original.data" \
    "$OUT/perf_optimized.data" \
    "$OUT/report_original.txt" \
    "$OUT/report_optimized.txt" \
    "$OUT/out_original.perf" \
    "$OUT/out_optimized.perf" \
    "$OUT/out_original.folded" \
    "$OUT/out_optimized.folded" \
    "$OUT/flamegraph_original.svg" \
    "$OUT/flamegraph_optimized.svg"

echo "[profile] Original Nbody at ${FREQUENCY} Hz"
perf record -F "$FREQUENCY" -g \
    -o "$OUT/perf_original.data" \
    python3-dbg "$BROOT/bm_nbody/run_benchmark.py"

perf report --stdio -i "$OUT/perf_original.data" \
    > "$OUT/report_original.txt"
perf script -i "$OUT/perf_original.data" \
    > "$OUT/out_original.perf"
"$FLAMEGRAPH/stackcollapse-perf.pl" "$OUT/out_original.perf" \
    > "$OUT/out_original.folded"
"$FLAMEGRAPH/flamegraph.pl" "$OUT/out_original.folded" \
    > "$OUT/flamegraph_original.svg"

echo "[profile] Best optimized Nbody (V1 scalar) at ${FREQUENCY} Hz"
perf record -F "$FREQUENCY" -g \
    -o "$OUT/perf_optimized.data" \
    python3-dbg "$SUBNBODY/software/run_benchmark_v1_scalar.py"

perf report --stdio -i "$OUT/perf_optimized.data" \
    > "$OUT/report_optimized.txt"
perf script -i "$OUT/perf_optimized.data" \
    > "$OUT/out_optimized.perf"
"$FLAMEGRAPH/stackcollapse-perf.pl" "$OUT/out_optimized.perf" \
    > "$OUT/out_optimized.folded"
"$FLAMEGRAPH/flamegraph.pl" "$OUT/out_optimized.folded" \
    > "$OUT/flamegraph_optimized.svg"

echo "[profile] Complete: $OUT"