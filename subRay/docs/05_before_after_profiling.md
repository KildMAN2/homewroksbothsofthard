# Before/After Profiling (Original vs Final)

## Scope and Profiling Approach

This comparison uses the same profiling tools used earlier:
- `perf stat` for supporting performance-counter context
- `py-spy` flame graph for readable Python stack visualization

Requested artifacts generated:
- `subRay/profiling/final_perf_stat.txt`
- `subRay/profiling/final_flamegraph_pyspy.svg`

## Workload and Comparability Notes

Original flame graph used for comparison:
- `subRay/profiling/flamegraph_pyspy_baseline.svg`
- Embedded command metadata shows:
	- `py-spy record --rate 100 --native`
	- `python3-dbg /root/.local/lib/python3.10/site-packages/pyperformance/data-files/benchmarks/bm_raytrace/run_benchmark.py`
	- `--width=64 --height=64`
	- no `--fast`

Final flame graph generated here:
- `subRay/profiling/final_flamegraph_pyspy.svg`
- Produced by reusing the existing Attempt 1 capture (`flamegraph_pyspy_attempt1.svg`) because `subRay/optimized/final/` is the same implementation as Attempt 1.
- Embedded command metadata shows:
	- `py-spy record --rate 100 --native`
	- `python3-dbg /root/homewroksbothsofthard/subRay/optimized/attempt1/run_benchmark.py`
	- `--width=64 --height=64`
	- no `--fast`

Comparability check from SVG metadata:

- Interpreter: both use `python3-dbg`
- Benchmark source path: baseline uses pyperformance `bm_raytrace/run_benchmark.py`; final uses optimized Attempt 1 `run_benchmark.py`
- Width/height: both use `--width=64 --height=64`
- `--fast`: absent in both
- py-spy rate: `--rate 100` in both
- `--native`: present in both

Therefore these two files are workload-compatible for direct qualitative flame-graph comparison. Observations below remain qualitative (not precise percentage claims).

## Observations from Flame Graphs

Interpretation reminder:
- Width = sampled runtime contribution
- Height = call-stack depth

### 1) Did the original hotspot become narrower?

Not claimed as a precise percentage change.

What is visible:
- In `flamegraph_pyspy_baseline.svg`, prominent sampled width appears around pyperf runner/manager and worker orchestration paths.
- In `final_flamegraph_pyspy.svg`, wide regions are still dominated by pyperf orchestration/worker communication paths.

Conclusion: the dominant stack families remain mostly in orchestration/control paths in both graphs; direct qualitative comparison is valid, but no exact narrowing percentage is claimed.

### 2) Did work shift elsewhere?

Yes, qualitatively in sampled stacks:
- Baseline graph prominently shows pyperf main/manager and worker flow.
- Final graph also shows strong worker/IPC-oriented paths such as `spawn_worker` -> `read_text` -> `read`.

This is treated as a qualitative stack-shape observation only.

### 3) Important function differences

From sampled frame labels:
- Original flame graph: strong presence of pyperf orchestration entry paths (`_main`, `bench_time_func`, manager creation paths) plus GC/import paths.
- Final reused flame graph: stronger worker communication/read path prominence, while still rooted in pyperf orchestration.

Application-kernel-level function ranking is not reliably isolated in these two captures because pyperf control-plane frames dominate.

### 4) Any new bottleneck?

Likely bottleneck in this profiling view is still pyperf control-plane overhead (worker spawn/read coordination) rather than a newly introduced raytrace algorithm bottleneck.

## Perf Stat Comparison (Baseline vs Final)

Artifacts:
- Baseline (non-fast): `subRay/profiling/perf_stat_baseline.txt`
- Final (non-fast): `subRay/profiling/perf_stat_final.txt`

| Metric | Baseline | Final |
|---|---:|---:|
| Elapsed time | 81.285 s (± 0.198, 3 runs) | 19.4335 s (single run) |
| cpu-clock | 80673 msec | 19204 msec |
| page-faults | 89,909 | 88,129 |
| context-switches | 2,459 | 704 |

Notes:
- The baseline capture recorded instruction/branch/cache counters; the final capture shows `<not supported>` for those PMU counters in that run, so only cpu-clock/task-clock/page-faults/context-switches are directly comparable.
- Elapsed time dropped ~4.1x, consistent with the official 81.285 s -> 19.7062 s result.
- Context-switches dropped substantially (2,459 -> 704), consistent with less work and a shorter run.

## Perf Report Comparison (Baseline vs Final)

Artifacts:
- Baseline: `subRay/profiling/perf_report.txt`
- Final: `subRay/profiling/perf_report_final.txt`

Top self-time symbol share:

| Symbol | Baseline | Final |
|---|---:|---:|
| `_PyEval_EvalFrameDefault` | 20.63% | 31.56% |

Interpretation:
- perf report percentages are RELATIVE shares of each run's samples, not absolute time.
- `_PyEval_EvalFrameDefault` grew in relative share (20.63% -> 31.56%) even though total runtime fell ~4.1x.
- The optimization removed large amounts of object/attribute/dict overhead (baseline families such as `_PyType_Lookup`, `dict_dealloc`, `lookdict_unicode_nodummy`), so the remaining core interpreter loop is a larger fraction of a much smaller total.
- The final report's next costs are arithmetic/boxing and frame handling (`binary_op1`, `float_*`, `PyFloat_FromDouble`, `frame_dealloc`, `call_function`), consistent with a tighter scalar compute path.
- A rising relative percentage is not a regression; wall-clock time and perf_stat elapsed both confirm the speedup.

## Relationship to Measured Speedup

Official timing results are still valid and strong:
- Original official mean: 81.285 s
- Final official mean: 19.7062 s
- Improvement: 75.76%

So the optimization clearly improved runtime. The flame-graph pair is suitable for qualitative comparison, while exact speedup attribution remains based on measured benchmark outputs.

## Recommendation for a Strict Apples-to-Apples Flamegraph Comparison

No re-run is required for qualitative comparison between `flamegraph_pyspy_baseline.svg` and `final_flamegraph_pyspy.svg`, because their command metadata already matches key workload settings.
