#!/usr/bin/env bash
set -euo pipefail

REPO=/root/homewroksbothsofthard
BROOT=/opt/pyperformance/pyperformance/data-files/benchmarks
OUT="$REPO/project_results/nbody"

mkdir -p "$OUT"

run_benchmark() {
    local label="$1"
    local script_path="$2"
    local output_name="$3"

    echo "[nbody] Running ${label}"
    python3-dbg "$script_path" --output "$OUT/$output_name"
}

# Baseline from pyperformance benchmark source.
run_benchmark "original (baseline)" "$BROOT/bm_nbody/run_benchmark.py" "baseline.json"

# Pure-Python optimized variants from repository.
run_benchmark "V1 scalar" "$REPO/bm_nbody/run_benchmark_v1_scalar.py" "v1_scalar.json"
run_benchmark "V2 unroll" "$REPO/bm_nbody/run_benchmark_v2_unroll.py" "v2_unroll.json"
run_benchmark "V3 sqrt" "$REPO/bm_nbody/run_benchmark_v3_sqrt.py" "v3_sqrt.json"
run_benchmark "V4 precompute" "$REPO/bm_nbody/run_benchmark_v4_precompute.py" "v4_precompute.json"
run_benchmark "final optimized" "$REPO/bm_nbody/run_benchmark_optimized.py" "optimized.json"

python3 - "$OUT" <<'PY'
import json
import statistics
import sys
from pathlib import Path

out_dir = Path(sys.argv[1])
rows = [
    ("original", "baseline.json"),
    ("V1 scalar", "v1_scalar.json"),
    ("V2 unroll", "v2_unroll.json"),
    ("V3 sqrt", "v3_sqrt.json"),
    ("V4 precompute", "v4_precompute.json"),
    ("final optimized", "optimized.json"),
]


def mean_time(path: Path) -> float:
    data = json.loads(path.read_text())
    values = []
    for bench in data.get("benchmarks", []):
        for run in bench.get("runs", []):
            values.extend(run.get("values", []))
    if not values:
        raise RuntimeError(f"No benchmark values in {path}")
    return statistics.mean(values)

means = {name: mean_time(out_dir / filename) for name, filename in rows}
baseline = means["original"]

lines = []
lines.append("Version | Mean Time | Speedup | Improvement %")
lines.append("---|---:|---:|---:")

for name, _ in rows:
    m = means[name]
    speedup = baseline / m
    improvement = ((baseline - m) / baseline) * 100.0
    lines.append(f"{name} | {m:.6f} s | {speedup:.4f}x | {improvement:.2f}%")

(out_dir / "optimization_comparison.txt").write_text("\n".join(lines) + "\n")
PY

echo "[nbody] Wrote:"
echo "  $OUT/baseline.json"
echo "  $OUT/v1_scalar.json"
echo "  $OUT/v2_unroll.json"
echo "  $OUT/v3_sqrt.json"
echo "  $OUT/v4_precompute.json"
echo "  $OUT/optimized.json"
echo "  $OUT/optimization_comparison.txt"
