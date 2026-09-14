# Nbody Original vs Best Optimization Profiling Commands

The measured optimization comparison identifies V1 scalar as the best variant:

- Original: 4.881335 seconds
- V1 scalar: 4.381726 seconds
- Speedup: 1.1140x
- Improvement: 10.24%

The final profiling compares the original benchmark with V1 scalar only. It uses the project PDF-style method, `perf record -F 999 -g`, without profiling any other variant. Older 499 Hz captures are retained only as historical/development artifacts.

## Run in the VM

```bash
cd /root/homewroksbothsofthard
bash subNbody/scripts/pdf_profile_and_fix_registration.sh
```

## Commands Executed by the Script

```bash
REPO=/root/homewroksbothsofthard
OUT="$REPO/project_results/nbody"

perf record -F 999 -g \
  -o "$OUT/perf_original_pdf.data" -- \
  python3-dbg -m pyperformance run --bench nbody

perf report --stdio -i "$OUT/perf_original_pdf.data" \
  > "$OUT/report_original_pdf.txt"
perf script -i "$OUT/perf_original_pdf.data" \
  > "$OUT/out_original_pdf.perf"
/opt/FlameGraph/stackcollapse-perf.pl "$OUT/out_original_pdf.perf" \
  > "$OUT/out_original_pdf.folded"
/opt/FlameGraph/flamegraph.pl "$OUT/out_original_pdf.folded" \
  > "$OUT/flamegraph_original_pdf.svg"

perf record -F 999 -g \
  -o "$OUT/perf_v1_pdf.data" -- \
  python3-dbg -m pyperformance run --bench nbody_v1

perf report --stdio -i "$OUT/perf_v1_pdf.data" \
  > "$OUT/report_v1_pdf.txt"
perf script -i "$OUT/perf_v1_pdf.data" \
  > "$OUT/out_v1_pdf.perf"
/opt/FlameGraph/stackcollapse-perf.pl "$OUT/out_v1_pdf.perf" \
  > "$OUT/out_v1_pdf.folded"
/opt/FlameGraph/flamegraph.pl "$OUT/out_v1_pdf.folded" \
  > "$OUT/flamegraph_v1_pdf.svg"
```

## Final Submission Artifacts

- `project_results/nbody/report_original_pdf.txt`
- `project_results/nbody/report_v1_pdf.txt`
- `project_results/nbody/flamegraph_original_pdf.svg`
- `project_results/nbody/flamegraph_v1_pdf.svg`

The final reports show `list_subscript` at about `1.62% -> 0.01%` and `PyObject_GetItem` at about `1.53% -> 0.04%`. V1 scalarization therefore reduced the repeated Python list-access overhead it targeted. Raw `perf.data`, `perf script`, and folded-stack files can regenerate the reports and flamegraphs but are not required submission artifacts.