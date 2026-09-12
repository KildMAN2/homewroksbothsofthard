#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
SUBNBODY=$(cd -- "$SCRIPT_DIR/.." && pwd)
BROOT=/opt/pyperformance/pyperformance/data-files/benchmarks
OUT="$SUBNBODY/results"

mkdir -p "$OUT"

cd "$BROOT"
python3-dbg bm_nbody/run_benchmark.py --output "$OUT/baseline.json"

perf record -F 999 -g -o "$OUT/perf.data" python3-dbg bm_nbody/run_benchmark.py
perf report --stdio -i "$OUT/perf.data" > "$OUT/report.txt"
perf script -i "$OUT/perf.data" > "$OUT/out.perf"
/opt/FlameGraph/stackcollapse-perf.pl "$OUT/out.perf" > "$OUT/out.folded"
/opt/FlameGraph/flamegraph.pl "$OUT/out.folded" > "$OUT/flamegraph_nbody.svg"

# Profile the best measured software implementation (V1 scalar).
python3-dbg "$SUBNBODY/software/run_benchmark_v1_scalar.py" --output "$OUT/optimized.json"

python3 -m pyperformance compare "$OUT/baseline.json" "$OUT/optimized.json" > "$OUT/compare.txt" || true

echo "nbody pipeline complete: $OUT"
