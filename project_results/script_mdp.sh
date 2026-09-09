#!/usr/bin/env bash
set -euo pipefail

REPO=/root/homewroksbothsofthard
BROOT=/opt/pyperformance/pyperformance/data-files/benchmarks
OUT="$REPO/project_results/mdp"

mkdir -p "$OUT"

cd "$BROOT"
python3-dbg bm_mdp/run_benchmark.py --output "$OUT/baseline.json"

perf record -F 999 -g -o "$OUT/perf.data" python3-dbg bm_mdp/run_benchmark.py
perf report --stdio -i "$OUT/perf.data" > "$OUT/report.txt"
perf script -i "$OUT/perf.data" > "$OUT/out.perf"
/opt/FlameGraph/stackcollapse-perf.pl "$OUT/out.perf" > "$OUT/out.folded"
/opt/FlameGraph/flamegraph.pl "$OUT/out.folded" > "$OUT/flamegraph_mdp.svg"

# Optimized run placeholder: point this to your optimized mdp script when available.
python3-dbg bm_mdp/run_benchmark.py --output "$OUT/optimized.json"

python3 -m pyperformance compare "$OUT/baseline.json" "$OUT/optimized.json" > "$OUT/compare.txt" || true

echo "mdp pipeline complete: $OUT"
