# Nbody Original vs Best Optimization Profiling Commands

The measured optimization comparison identifies V1 scalar as the best variant:

- Original: 4.881335 seconds
- V1 scalar: 4.381726 seconds
- Speedup: 1.1140x
- Improvement: 10.24%

The profiling script therefore compares the original benchmark with V1 scalar only. It uses `perf record -F 499 -g`, a moderate sampling frequency that captures call stacks without profiling every variant.

## Run in the VM

```bash
cd /root/homewroksbothsofthard
git pull --rebase origin master
chmod +x subNbody/scripts/profile_nbody_best.sh
bash subNbody/scripts/profile_nbody_best.sh
```

## Commands Executed by the Script

```bash
REPO=/root/homewroksbothsofthard
BROOT=/opt/pyperformance/pyperformance/data-files/benchmarks
OUT="$REPO/project_results/nbody"

perf record -F 499 -g \
  -o "$OUT/perf_original.data" \
  python3-dbg "$BROOT/bm_nbody/run_benchmark.py"

perf report --stdio -i "$OUT/perf_original.data" \
  > "$OUT/report_original.txt"
perf script -i "$OUT/perf_original.data" \
  > "$OUT/out_original.perf"
/opt/FlameGraph/stackcollapse-perf.pl "$OUT/out_original.perf" \
  > "$OUT/out_original.folded"
/opt/FlameGraph/flamegraph.pl "$OUT/out_original.folded" \
  > "$OUT/flamegraph_original.svg"

perf record -F 499 -g \
  -o "$OUT/perf_optimized.data" \
  python3-dbg "$REPO/subNbody/software/run_benchmark_v1_scalar.py"

perf report --stdio -i "$OUT/perf_optimized.data" \
  > "$OUT/report_optimized.txt"
perf script -i "$OUT/perf_optimized.data" \
  > "$OUT/out_optimized.perf"
/opt/FlameGraph/stackcollapse-perf.pl "$OUT/out_optimized.perf" \
  > "$OUT/out_optimized.folded"
/opt/FlameGraph/flamegraph.pl "$OUT/out_optimized.folded" \
  > "$OUT/flamegraph_optimized.svg"
```

## Commit Results from the VM

```bash
cd /root/homewroksbothsofthard
git add \
  subNbody/results/perf_original.data \
  subNbody/results/perf_optimized.data \
  subNbody/results/report_original.txt \
  subNbody/results/report_optimized.txt \
  subNbody/results/flamegraph_original.svg \
  subNbody/results/flamegraph_optimized.svg
git commit -m "Add original and best Nbody profiling artifacts"
git push origin master
```

The intermediate `out_*.perf` and `out_*.folded` files are useful for regenerating flamegraphs but are not required by the requested deliverables.