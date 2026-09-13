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
- `subRay/profiling/flamegraph_pyspy.svg`
- Embedded command shows baseline raytrace with `--fast --width=64 --height=64`

Final flame graph generated here:
- `subRay/profiling/final_flamegraph_pyspy.svg`
- Produced by reusing the existing Attempt 1 capture (`flamegraph_pyspy_attempt1.svg`) because `subRay/optimized/final/` is the same implementation as Attempt 1.
- Embedded command in this reused capture is `--width=64 --height=64` (no `--fast`).

Because these two flame graphs come from different workload modes (`--fast` vs non-fast), direct width-to-width quantitative comparison is not valid. The observations below are qualitative only.

## Observations from Flame Graphs

Interpretation reminder:
- Width = sampled runtime contribution
- Height = call-stack depth

### 1) Did the original hotspot become narrower?

Not conclusively measurable from these two specific files because workload modes differ.

What is visible:
- In `flamegraph_pyspy.svg` (original, fast), prominent sampled width appears around pyperf runner/manager and module startup paths.
- In `final_flamegraph_pyspy.svg` (final via attempt1, non-fast), wide regions are still dominated by pyperf orchestration/worker communication paths.

Conclusion: no reliable claim of a specific hotspot narrowing from this pair alone.

### 2) Did work shift elsewhere?

Yes, qualitatively in sampled stacks:
- Original (fast) prominently shows pyperf main/manager and GC/import-related paths.
- Final reused profile (non-fast) shows stronger concentration in pyperf worker/IPC paths such as `spawn_worker` -> `read_text` -> `read`.

This is a stack-shape shift, but because workloads differ it should be treated as contextual rather than causal.

### 3) Important function differences

From sampled frame labels:
- Original flame graph: strong presence of pyperf orchestration entry paths (`_main`, `bench_time_func`, manager creation paths) plus GC/import paths.
- Final reused flame graph: stronger worker communication/read path prominence, while still rooted in pyperf orchestration.

Application-kernel-level function ranking is not reliably isolated in these two captures because pyperf control-plane frames dominate.

### 4) Any new bottleneck?

Likely bottleneck in this profiling view is still pyperf control-plane overhead (worker spawn/read coordination) rather than a newly introduced raytrace algorithm bottleneck.

## Relationship to Measured Speedup

Official timing results are still valid and strong:
- Original official mean: 81.285 s
- Final official mean: 19.7062 s
- Improvement: 75.76%

So the optimization clearly improved runtime, even though this specific original-vs-final flamegraph pair is not workload-matched for strict visual width comparison.

## Recommendation for a Strict Apples-to-Apples Flamegraph Comparison

For strict visual comparison, regenerate final py-spy using the same mode as original reference (`--fast`, same width/height, same host), then compare that regenerated final graph against `flamegraph_pyspy.svg`.
