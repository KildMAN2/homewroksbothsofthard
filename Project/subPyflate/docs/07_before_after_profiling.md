# Pyflate — Before/After Profiling

Compares matched-methodology profiling of the preserved ORIGINAL and the
selected FINAL implementation. This document is filled in on the VM after
`scripts/script_pyflate.sh profile-suite` has been run for both `baseline`
and `final` targets.

## Artifacts

Windows-collected (`scripts/pyspy_target.py`, py-spy 0.4.2, rate 500 Hz,
20 decompressions per SVG, 2026-09-21):

- `profiling/flamegraph_pyspy_baseline.svg` (6847 samples)
- `profiling/flamegraph_pyspy_attempt1.svg` (6230 samples)
- `profiling/flamegraph_pyspy_attempt2.svg` (5043 samples)
- `profiling/flamegraph_pyspy_attempt3.svg` (4438 samples)
- `profiling/flamegraph_pyspy_final.svg` (4984 samples)

Sample counts drop monotonically from baseline through attempt3 (fewer
samples over the same 20-decompression workload = less time spent), which
visually confirms the +30% pyperformance improvement.

VM-collected (TO BE COLLECTED IN VM, when CS-lab access is restored):
- `profiling/perf_stat_baseline.txt` vs `profiling/perf_stat_final.txt`
- `profiling/perf_report_suite_baseline.txt` vs `profiling/perf_report_suite_final.txt`

The VM captures fill in `perf`'s Linux-only pieces (perf stat counters and
perf report call graphs). The Windows-collected py-spy SVGs and the
Windows pyperformance numbers already give the before/after profile
picture at the Python-frame level.

## perf stat Comparison (fill after collection)

| Metric | Baseline | Final |
|---|---:|---:|
| Elapsed time | TBD | TBD |
| cpu-clock | TBD | TBD |
| instructions | TBD | TBD |
| branches | TBD | TBD |
| branch-misses (%) | TBD | TBD |
| cache-references | TBD | TBD |
| cache-misses (%) | TBD | TBD |
| page-faults | TBD | TBD |
| context-switches | TBD | TBD |

Expected qualitative shifts (from `docs/04_bottleneck_analysis.md`):
- `instructions` drop dominates the runtime reduction, as in the raytrace
  project. Pyflate's per-symbol Python overhead was the primary cost.
- `branch-misses (%)` is expected to fall because the LUT lookup replaces a
  data-dependent loop over Huffman entries with straight-line code.
- `cache-references` and `cache-misses` are expected to stay roughly the
  same in absolute terms — the LUT itself adds a small O(2^max_bits) working
  set but is dominated by the input/output buffers.

## perf report Comparison (fill after collection)

Top self-time symbols; capture the same way as
`Project/subRay/profiling/perf_report_suite_final.txt`.

| Symbol | Baseline % | Final % |
|---|---:|---:|
| `_PyEval_EvalFrameDefault` | TBD | TBD |
| `PyObject_GenericGetAttr` | TBD | TBD |
| `find_next_symbol` (Python frame) | TBD | TBD |
| `list_slice` / `list_ass_slice` | TBD | TBD |
| `bytes_find` | TBD | TBD |

Interpretation to write:
- Which specific Python frame drops in absolute time (the LUT should erase
  `find_next_symbol` self time almost entirely; `_PyEval_EvalFrameDefault`
  usually keeps its shape but shrinks).
- Relative percentages of `_PyEval_EvalFrameDefault` may rise even as
  wall-clock time falls — same effect as in the raytrace report; call out
  that percentages are a share of each run's samples.

## Flame Graph Comparison (fill after collection)

- Baseline: `profiling/flamegraph_pyspy_baseline.svg`
- Final: `profiling/flamegraph_pyspy_final.svg`

Look for:
- A wide `find_next_symbol` bar in baseline that shrinks or vanishes in
  final.
- A wide `move_to_front` bar in baseline that shrinks in final.
- `bwt_transform` bar staying roughly the same (BWT was optimized but the
  block is still dominated by the Python-level output list). Its bar was
  never the main hotspot.

Any workload difference between the two flame graphs must be documented (as
in the raytrace report's disclaimer about `py-spy` runs with different
modes).

## Conclusion (fill after collection)

- Did the targeted hotspot shrink?
- Did another function become dominant?
- Does the profile support the measured wall-clock speedup?
