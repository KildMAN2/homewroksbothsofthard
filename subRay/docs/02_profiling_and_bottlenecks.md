# Additional Python-Level Flame Graph

This supplemental step adds a second profiling path intended to improve Python-level readability while preserving all existing profiling evidence.

The original perf-based profiling remains preserved and valid:
- Existing profiling artifacts were left untouched in [subRay/profiling](subRay/profiling).
- The prior flame graph was preserved under a descriptive name: [subRay/profiling/flamegraph_original.svg](subRay/profiling/flamegraph_original.svg).
- Existing perf reports, logs, and benchmark results were not removed or replaced.

Why add a second graph:
- perf flame graphs can include many low-level or unresolved frames in VM environments.
- py-spy often shows clearer Python function names and benchmark call hierarchy.
- This py-spy graph is supplemental and does not replace prior perf evidence.

## Supplemental py-spy Flame Graph Result

Status:
- py-spy availability check in VM failed: `py-spy: command not found`.
- Per instruction, package installation was not performed.
- Therefore [subRay/profiling/flamegraph_pyspy.svg](subRay/profiling/flamegraph_pyspy.svg) was not generated in this step.

Exact command used to verify py-spy:
- `py-spy --version`

Actual benchmark workload command identified from baseline evidence:
- `.../venv/.../python -u /usr/local/lib/python3.10/dist-packages/pyperformance/data-files/benchmarks/bm_raytrace/run_benchmark.py --output <tmp> --inherit-environ PYPERFORMANCE_RUNID`

Direct raytrace command used for cheap supplemental measurement support:
- `python3-dbg /usr/local/lib/python3.10/dist-packages/pyperformance/data-files/benchmarks/bm_raytrace/run_benchmark.py --fast --width=64 --height=64`

Requested py-spy command template (not executed due missing tool):
- `py-spy record --rate 100 --native --output subRay/profiling/flamegraph_pyspy.svg -- <actual_raytrace_command>`

Sampling configuration for the planned py-spy run:
- Sampling rate: 100 Hz
- Native frames: yes
- Subprocess tracing: no (direct benchmark command, no worker launcher used)
- Output filename: [subRay/profiling/flamegraph_pyspy.svg](subRay/profiling/flamegraph_pyspy.svg)

3-5 widest benchmark-specific functions:
- Not available in this step because py-spy output was not generated.

Remaining limitations:
- Missing py-spy binary in VM blocks supplemental Python-level flame graph generation.
- VM perf environment reports some unsupported hardware counters.

## Measured Facts

The following facts were measured directly in VM during this supplemental step:
- Preserved prior flame graph copy exists: [subRay/profiling/flamegraph_original.svg](subRay/profiling/flamegraph_original.svg).
- Supplemental perf stat output exists: [subRay/profiling/perf_stat.txt](subRay/profiling/perf_stat.txt).
- Supplemental perf stat benchmark stdout exists: [subRay/profiling/perf_stat_stdout.txt](subRay/profiling/perf_stat_stdout.txt).

perf stat command used:
- `perf stat -r 3 -e cpu-clock,task-clock,cycles,instructions,branch-instructions,branch-misses -- python3-dbg /usr/local/lib/python3.10/dist-packages/pyperformance/data-files/benchmarks/bm_raytrace/run_benchmark.py --fast --width=64 --height=64`

perf stat key results:
- cpu-clock: 19289.52 ms (+/- 1.67%)
- task-clock: 19289.91 ms (+/- 1.66%)
- elapsed: 19.103 s (+/- 1.72%)
- unsupported counters: cycles, instructions, branch-instructions, branch-misses

Benchmark summaries from the same 3-run supplemental command:
- raytrace: 500 ms +/- 56 ms
- raytrace: 483 ms +/- 23 ms
- raytrace: 503 ms +/- 48 ms

## Interpretation

The supplemental perf stat run confirms that the reduced direct workload is inexpensive enough for additional profiling and still exhibits jitter in the VM environment.

Because py-spy is unavailable, no new Python-level flame graph evidence was produced in this step.

Previous bottleneck conclusions remain unchanged for now. A re-check should be done after py-spy is installed and [subRay/profiling/flamegraph_pyspy.svg](subRay/profiling/flamegraph_pyspy.svg) is generated.

# Later py-spy Profiling Update

The historical record above remains correct for that earlier step: py-spy was initially unavailable in that VM stage.

Later in the project, py-spy profiling was run successfully and the following artifacts now exist:

- [subRay/profiling/flamegraph_pyspy_baseline.svg](subRay/profiling/flamegraph_pyspy_baseline.svg)
- [subRay/profiling/flamegraph_pyspy_final.svg](subRay/profiling/flamegraph_pyspy_final.svg)

Embedded command metadata read directly from SVG titles:

- `flamegraph_pyspy_baseline.svg`
	- `py-spy record --rate 100 --native`
	- `--output /root/homewroksbothsofthard/subRay/profiling/flamegraph_pyspy_baseline.svg`
	- `-- python3-dbg /root/.local/lib/python3.10/site-packages/pyperformance/data-files/benchmarks/bm_raytrace/run_benchmark.py --width=64 --height=64`

- `flamegraph_pyspy_final.svg`
	- `py-spy record --rate 100 --native`
	- `--output /root/homewroksbothsofthard/subRay/profiling/flamegraph_pyspy_final.svg`
	- `-- python3-dbg /root/homewroksbothsofthard/subRay/optimized/final/run_benchmark.py --width=64 --height=64`

What this later py-spy evidence adds on top of perf:

- It provides readable Python call-path names that complement perf's lower-level symbol-heavy view.
- It confirms the profiling command path details used for baseline and final software traces (interpreter, script path, width, height, py-spy rate, and `--native`).
- It supports qualitative before/after call-stack discussion while preserving perf as the primary measured hotspot source.
