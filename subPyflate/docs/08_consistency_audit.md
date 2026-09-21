# Pyflate — Consistency Audit

Fills after VM measurement to check the documentation against the actual
saved evidence. Same intent as `subRay/docs/07_optimization_experiments.md`
and the raytrace consistency check that flagged mismatched flame-graph
workloads.

## Checklist

- [ ] Every `TO BE COLLECTED IN VM` placeholder in `docs/02..07` has been
      replaced with a real measurement or explicitly explained as still
      pending.
- [ ] `results/original_official.txt` and `results/final_official.txt`
      exist and were produced with matched pyperformance methodology.
- [ ] Improvement % in `docs/06_final_software.md` matches
      `(original_mean - final_mean) / original_mean * 100`.
- [ ] `results/attempt{1,2,3}/correctness_report.txt` and
      `results/final/correctness_report.txt` all show `IDENTICAL=YES` and
      `MATCHES_REFERENCE=YES`.
- [ ] `profiling/perf_stat_*.txt` files exist for baseline and final.
- [ ] `profiling/flamegraph_pyspy_baseline.svg` and
      `profiling/flamegraph_pyspy_final.svg` were generated with the same
      workload; if not, the difference is disclosed in
      `docs/07_before_after_profiling.md`.
- [ ] `hw/results/SIMULATION_RESULTS.txt` records simulator, exact
      command, and pass/fail totals for every testbench.
- [ ] `docs/13_hardware_performance.md` marks every hardware number as
      ESTIMATE.

## Verified

`TO BE COMPLETED AFTER VM RUN.`

## Corrected

`TO BE COMPLETED AFTER VM RUN.`

## Evidence-Based Unresolved Items

`TO BE COMPLETED AFTER VM RUN.`

## Final Verified Numbers

`TO BE COMPLETED AFTER VM RUN.`
