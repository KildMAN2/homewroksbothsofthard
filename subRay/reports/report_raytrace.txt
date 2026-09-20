# Raytrace Benchmark Report

## 1. Overview

This report consolidates the Raytrace project from baseline through software optimization, profiling, hardware design, interface planning, RTL simulation, and hardware performance estimation.

Scope and evidence policy:
- All claims are based on project artifacts under `subRay/docs/`, `subRay/results/`, `subRay/profiling/`, and `subRay/hw/results/`.
- Measured results are explicitly separated from estimates.
- No information in this report is invented.

Primary final outcome:
- Best software version selected: `subRay/optimized/final/` (copied from Attempt 1).
- Official measured improvement versus original: **75.76%**.
- 7% target status: **achieved**.

## 2. Benchmark Purpose

The benchmark is `raytrace` from pyperformance. It measures execution time of a pure-Python ray tracer that performs:
- camera ray generation,
- ray-object intersection testing,
- recursive reflection,
- shadow visibility checks,
- diffuse/specular/ambient shading,
- per-pixel RGB output writes.

The optimization objective was to improve performance while preserving correctness and keeping the original benchmark source unchanged.

## 3. Libraries and Dependencies

Runtime/software:
- Python 3.10.12 (documented in baseline environment records).
- `python3-dbg` for profiling-friendly symbol visibility.
- `pyperformance 1.14.0` / `pyperf` benchmark framework.
- Python stdlib modules used by benchmark implementation: `array`, `math`.

Profiling/tools:
- `perf` (`perf record`, `perf report`, `perf stat`).
- `py-spy` for Python flame graphs (available in later profiling runs).

Hardware design and verification:
- SystemVerilog RTL in `subRay/hw/rtl/`.
- SystemVerilog testbenches in `subRay/hw/tb/`.
- ModelSim Intel FPGA Edition 10.5b (`vlog`, `vsim`) for simulation.

## 4. Data Structures

Original benchmark uses object-oriented geometry and scene modeling:
- Classes: `Vector`, `Point`, `Ray`, `Sphere`, `Halfspace`, `Canvas`, `Scene`, `SimpleSurface`, `CheckerboardSurface`.
- Scene containers:
  - object list of `(geometry, surface)` tuples,
  - light-point list.
- Per-ray temporary intersection list in original `rayColour` path.
- RGB storage in `array.array('B')` for canvas bytes.

Optimized software attempts progressively replaced hot-path object/method usage with scalar float locals and tuple-based scene data.

## 5. Algorithm

Core algorithm flow:
1. Build camera basis and per-pixel primary ray.
2. Intersect ray against all scene objects (spheres and halfspace/plane).
3. Select nearest valid hit.
4. Compute shading:
   - recursive specular reflection,
   - Lambert diffuse from visible lights,
   - ambient contribution.
5. For each light, cast a shadow ray and test visibility.
6. Clamp and write RGB pixel.

Complexity characteristics:
- High constant-factor Python overhead due heavy per-ray/per-pixel object and method activity.
- Intersection and shading loops are repeated across all pixels and recursion/light paths.

## 6. Original Implementation

Original benchmark source was preserved under:
- `subRay/original/bm_raytrace/run_benchmark.py`
- `subRay/original/bm_raytrace/pyproject.toml`

Integrity controls:
- SHA256 checks recorded and matched against source copy evidence in benchmark-understanding documentation.
- Original source was not modified during optimization work.

## 7. Baseline Performance

Early baseline run summary (from `subRay/reports/baseline_results.txt`):
- Mean: **26.8 s**
- Std dev: **5.7 s**
- Max: **48.7 s**
- Warning: benchmark may be unstable.

Important context:
- This early baseline was noisy and carried instability warnings in the VM.
- The final official before/after comparison used dedicated official measurement files and is reported in Section 15.

## 8. Profiling Methodology

### pyperformance
- Used to run the benchmark with pyperf statistical methodology.
- Provides mean/std-dev style outputs and stability warnings.

### perf
- `perf record -F 999 -g` used to capture sampled call stacks.
- `perf report --stdio` used for hotspot extraction.
- `perf stat` used for counter-based support data and repeatability context.

### py-spy
- Used for readable Python flame graphs.
- Helpful when perf stacks include unresolved/noisy low-level frames.
- Workload matching caveat documented when comparing graphs from different modes.

Method controls:
- Preserve raw artifacts.
- Keep failed attempts/warnings visible.
- Avoid rerunning expensive profiling when equivalent evidence already exists.

## 9. Original Flame Graph Analysis

Original flame graph artifacts include:
- `subRay/profiling/flamegraph.svg`
- `subRay/profiling/flamegraph_original.svg`
- `subRay/profiling/flamegraph_pyspy.svg`

Observed behavior (cross-checked with perf report evidence):
- Broad runtime share in Python interpreter/control-plane paths.
- Significant stack presence associated with frame evaluation, Python arithmetic dispatch, lookup/deallocation activity, and benchmark orchestration.

Interpretation boundary:
- Flame-graph width was used qualitatively to locate hotspots.
- Exact percentages were taken from perf report text where available.

## 10. Bottlenecks

Measured hotspot families from profiling artifacts:
- `_PyEval_EvalFrameDefault` around ~20.6% to ~23.6% in key reports.
- `_PyEval_MakeFrameVector`, `_PyFrame_New_NoTrack`, `frame_dealloc`.
- `binary_op1`, `PyFloat_FromDouble`, `PyTuple_GetItem`.
- `_PyObject_GetMethod`, `_PyType_Lookup`, dictionary lookup/deallocation helpers.

Conclusion from measured data:
- Dominant costs are Python interpreter/object overhead plus repeated scalar geometry arithmetic in hot loops, not one isolated native library kernel.

## 11. Optimization Candidates

Ranked candidate categories documented and reviewed:
1. Scalarize hot vector/point/ray arithmetic and reduce object churn.
2. Remove per-ray temporary intersections list and fold nearest-hit selection into one pass.
3. Hoist repeated global/attribute/helper lookups.
4. Reduce dictionary/object overhead patterns.
5. Shading/visibility loop refactors.
6. Pixel-write path micro-optimizations.

Hardware candidate selection (separate phase):
- Sphere/plane intersection + closest-hit reduction (including visibility blockers) selected as first accelerator target.

## 12. Optimization Attempts

### Attempt 1
- Strategy: scalar float locals + tuple-based scene data in the hottest vector/point/ray paths.
- Effect: introduced the main scalarization optimization and produced almost the entire software speedup.
- Correctness: `IDENTICAL=YES` (`subRay/results/attempt1/correctness_report.txt`).

### Attempt 2
- Strategy: local alias/lookup hoisting for hot globals/helpers in `ray_colour()` and `bench_raytrace()`.
- Correctness: `IDENTICAL=YES` (`subRay/results/attempt2_correctness_report.txt`).

### Attempt 3
- Strategy: inlined the per-light visibility check in the Lambert loop to reduce call/frame overhead.
- Correctness: `IDENTICAL=YES` (`subRay/results/attempt3_correctness_report.txt`).

### Measured non-fast `perf stat` comparison
- Attempt 1: `19.7062 ± 0.0133 s`
- Attempt 2: `19.68433 ± 0.00708 s`
- Attempt 3: `19.6077 ± 0.0171 s`

Notes:
- Attempt 3 was slightly faster than Attempt 1 in this later non-fast `perf stat` comparison.
- Attempt 1 remains the official final implementation because the locked official result and the final submission pipeline were produced from Attempt 1.
- Attempt 1 is not claimed to be the fastest in every measurement.
- Earlier supplemental profiling step documented `py-spy` unavailable in one VM stage (`py-spy: command not found`), so that specific requested graph was not generated in that step.
- Local virtualization/PMU limitations were encountered in some environments (hardware counters unsupported), so PMU-capable runs were done where supported.

## 13. Final Software Optimization

Selected final software implementation:
- `subRay/optimized/final/` (copied from Attempt 1).

Selection basis:
- Attempt 1 introduced the main scalarization optimization and produced almost the entire software speedup.
- Attempt 1 is the locked official final because the official before/after result and the final submission pipeline were generated from Attempt 1.
- Attempt 3 was slightly faster in the later non-fast `perf stat` comparison, but it is not the locked official final.

Measured non-fast `perf stat` means:

| Version | Correct | perf stat mean (non-fast) |
|---|---|---:|
| Attempt 1 | Yes | 19.7062 ± 0.0133 s |
| Attempt 2 | Yes | 19.68433 ± 0.00708 s |
| Attempt 3 | Yes | 19.6077 ± 0.0171 s |

## 14. Correctness Verification

Correctness checks used deterministic output comparison and SHA256 reporting at a fixed `32×32` scene.

Documented outcomes:
- Attempt 1: `IDENTICAL=YES` with matching hash (`subRay/results/attempt1/correctness_report.txt`).
- Attempt 2: `IDENTICAL=YES` with matching hash (`subRay/results/attempt2_correctness_report.txt`).
- Attempt 3: `IDENTICAL=YES` with matching hash (`subRay/results/attempt3_correctness_report.txt`).

Verification artifacts:
- `subRay/results/attempt1/correctness_report.txt`
- `subRay/results/attempt2_correctness_report.txt`
- `subRay/results/attempt3_correctness_report.txt`
- checker scripts under `subRay/scripts/`

Scope of this evidence:
- Exact byte/SHA256 equality proves the optimized output matches the original for the tested fixed scene and `32×32` resolution.
- It does not prove correctness for every possible input, scene, or resolution.

## 15. Official Before/After Performance

Official measurement files:
- Original: `subRay/results/original_official.txt`
- Final: `subRay/results/final_official.txt`

These are matched `perf stat` elapsed measurements over three complete benchmark-script executions at `64×64` (not the time to render a single image).

Official results:

| Version | Mean | Std Dev | Improvement | Correct |
|---|---:|---:|---:|---|
| ORIGINAL | 81.285 s | 0.198 s | 0.00% | Yes |
| FINAL (Attempt 1) | 19.7062 s | 0.0133 s | 75.76% | Yes |

- Speedup: approximately `4.12x` (`81.285 / 19.7062`).
- Runtime improvement: `75.76%`.

Threshold check:
- Target `>= 7%` improvement: **achieved**.

## 15A. Perf Stat Comparison (Baseline vs Final)

Artifacts:
- Baseline (non-fast): `subRay/profiling/perf_stat_baseline.txt`
- Final (non-fast): `subRay/profiling/perf_stat_final.txt`

| Metric | Baseline (mean of 3 runs) | Final (single run) |
|---|---:|---:|
| Elapsed time | 81.285 s | 19.667 s |
| cpu-clock | 80,673 msec | 19,415 msec |
| instructions | 387,324,411,814 | 99,522,163,151 |
| cache-references | 404,917,856 | 198,261,770 |
| cache-misses | 4,285,182 (1.045%) | 2,925,764 (1.476%) |
| branches | 94,415,979,904 | 23,673,592,504 |
| branch-misses | 865,418,173 (0.91%) | 166,181,093 (0.70%) |
| page-faults | 89,909 | 87,875 |
| context-switches | 2,459 | 2,101 |

Notes:
- Instructions retired dropped ~3.9x (387.3B -> 99.5B); this is the primary driver of the ~4.1x runtime reduction.
- Branches dropped ~4.0x (94.4B -> 23.7B) and branch-misses fell ~5.2x, reflecting far less interpreter/object dispatch work.
- Cache-references roughly halved (405M -> 198M); the cache-miss rate rose slightly (1.045% -> 1.476%) but absolute misses still fell.
- Elapsed time dropped from 81.285 s to 19.667 s (~4.1x), consistent with the official 81.285 s -> 19.7062 s result.
- The `cpu-cycles` counter reads `0` because the PMU cycle counter was unavailable in this environment, not because execution used zero cycles.

## 15B. Perf Report Comparison (Baseline vs Final)

Artifacts:
- Baseline: `subRay/profiling/perf_report_suite_baseline.txt`
- Final: `subRay/profiling/perf_report_suite_final.txt`

Top self-time symbol share:

| Metric | Baseline | Final |
|---|---:|---:|
| Samples (cpu-clock) | 117K | 34K |
| `_PyEval_EvalFrameDefault` | 23.50% | 27.39% |

Interpretation:
- The `perf_report_suite_*.txt` pair is the authoritative, matched-methodology capture (baseline via `run_baseline.sh`, final via the `raytrace_final` manifest, both through the identical pyperformance harness invocation), superseding the earlier `perf_report_baseline.txt`/`perf_report_final.txt` pair.
- perf report percentages are RELATIVE shares of each run's samples, not absolute time.
- Sample counts differ (117K vs 34K) because perf samples at a fixed rate and the baseline runs much longer than the final; both are large enough for a stable top-symbol ranking.
- The interpreter dispatch loop `_PyEval_EvalFrameDefault` grew in relative share (23.50% -> 27.39%) even though total runtime fell ~4.1x.
- This is expected: the optimization removed large amounts of object/attribute/dict overhead (baseline families such as `_PyType_Lookup`, `dict_dealloc`, `lookdict_unicode_nodummy`), so the remaining core interpreter loop is a bigger fraction of a much smaller total.
- In the final report the next costs are arithmetic/boxing and frame handling (`binary_op1`, `float_*`, `PyFloat_FromDouble`, `frame_dealloc`, `call_function`), consistent with a tighter scalar compute path.
- Conclusion: a rising relative percentage does NOT mean regression; wall-clock time and perf_stat elapsed both confirm the speedup.

## 16. Before/After Flame Graph Comparison

Primary matched full-suite flame-graph artifacts:
- Baseline: `subRay/profiling/flamegraph_suite_baseline.svg`
- Final: `subRay/profiling/flamegraph_suite_final.svg`

Authoritative matched profiling reports (same captures):
- Baseline: `subRay/profiling/perf_report_suite_baseline.txt` (`_PyEval_EvalFrameDefault` approximately `23.50%`)
- Final: `subRay/profiling/perf_report_suite_final.txt` (`_PyEval_EvalFrameDefault` approximately `27.39%`)

Interpretation:
- These percentages are relative shares of each run's samples. The final `_PyEval_EvalFrameDefault` share can increase even while total runtime decreases, because other object, lookup, dictionary, and allocation overhead was removed, leaving the core interpreter loop as a larger fraction of a much smaller total.

py-spy flame graphs (supplemental only):
- `subRay/profiling/flamegraph_pyspy_baseline.svg` and `subRay/profiling/flamegraph_pyspy_final.svg` are preserved as supplemental historical evidence.
- They contain very few samples and mainly show pyperf manager/import/worker-control paths.
- The profiling script currently defaults to `PYSPY_SUBPROCESSES=0`, and pyperf launches benchmark workers as subprocesses, so these py-spy graphs do not capture the benchmark kernel and should not be treated as primary kernel evidence.

## 17. Hardware Acceleration Motivation

Why hardware was pursued:
- Software profiling showed persistent heavy numeric/interpreter overhead in intersection-heavy hot paths.
- Intersection and closest-hit logic are high-frequency, arithmetic-dense, and structurally suitable for hardware pipelining/parallelism.

Evidence boundaries (kept explicit):

IMPLEMENTED:
- Q16.16 fixed-point RTL modules in `subRay/hw/rtl/` (`fxp_sqrt.sv`, `sphere_intersect.sv`, `intersect_accel.sv`).
- Direct testbench port-level interface in `subRay/hw/tb/`.

SIMULATED:
- ModelSim compile: 0 errors, 0 warnings.
- All `18/18` functional checks passed (`tb_fxp_sqrt`: 11, `tb_intersect_accel`: 7); evidence in `subRay/hw/results/`.

ESTIMATED (not measured):
- `200 MHz` target clock, cycles/ray, throughput, Amdahl-based speedups, area, power, and bandwidth (see `subRay/docs/09_hardware_performance.md`).

PROPOSED (not implemented):
- MMIO register map, DMA, input/output buffering, Python/C wrapper, driver, and real FPGA integration (see `subRay/docs/08_hw_sw_interface.md`).

Architecture note:
- The RTL implemented and simulated so far is the iterative Q16.16 v1 design.
- The higher-performance estimates (cycles/ray, throughput, speedups) refer to a future pipelined, multi-lane target architecture, not the current iterative v1.

No claim is made of synthesis, FPGA deployment, measured hardware speedup, measured area, measured power, or measured operating frequency.

## 18. Final Conclusions and Remaining Work

Conclusions:
- The Raytrace project produced a verified and substantially faster software final version.
- Official measured software gain is **75.76%**, far exceeding the 7% requirement.
- Correctness was preserved for evaluated attempts used in final selection workflow.
- Hardware accelerator RTL and testbench are implemented and simulation-verified, with interface and performance plans documented.

Remaining work to transition from prototype to measured hardware acceleration:
- Implement real HW/SW runtime integration (driver/wrapper, register map/DMA path).
- Run apples-to-apples workload-matched before/after flame graphs if strict visual comparison is needed.
- Perform synthesis/place-route for real area/timing/power numbers.
- Execute hardware-in-the-loop benchmarking to replace Amdahl-based estimates with measured end-to-end acceleration.
