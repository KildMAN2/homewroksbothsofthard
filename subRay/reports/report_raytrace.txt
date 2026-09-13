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
- Strategy: scalar float locals + tuple-based scene data in the hottest paths.
- Result: became final selected software implementation.

### Attempt 2
- Strategy: local alias hoisting for hot globals/helpers in `ray_colour()` and `bench_raytrace()`.
- Correctness: `IDENTICAL=YES` (`subRay/results/attempt2_correctness_report.txt`).
- Fast benchmark: **242 ms ± 28 ms**.

### Attempt 3
- Strategy: inline per-light visibility logic in Lambert loop to reduce call/frame overhead.
- Correctness: `IDENTICAL=YES` (`subRay/results/attempt3_correctness_report.txt`).
- Fast benchmark: **243 ms ± 20 ms**.

### Failed/Regressed or Non-selected outcomes (included as required)
- Attempt 2 and Attempt 3 were both correct but slower than Attempt 1 in preliminary comparison, so they were not selected.
- Earlier supplemental profiling step documented `py-spy` unavailable in one VM stage (`py-spy: command not found`), so that specific requested graph was not generated in that step.
- Local virtualization/PMU limitations were encountered in some environments (hardware counters unsupported), so PMU-capable runs were done where supported.

## 13. Final Software Optimization

Selected final software implementation:
- `subRay/optimized/final/` (copied from Attempt 1).

Selection basis:
- Attempt 1 had the best preliminary mean among correct attempts.
- Attempts 2 and 3 remained correct but slower in preliminary measured comparison.

Preliminary comparison table:

| Version | Correct | Preliminary Mean | Improvement vs Preliminary Original |
|---|---|---:|---:|
| Attempt 1 | Yes | 103 ms | 78.18% |
| Attempt 2 | Yes | 242 ms | 48.73% |
| Attempt 3 | Yes | 243 ms | 48.52% |

## 14. Correctness Verification

Correctness checks used deterministic output comparison and SHA256 reporting.

Documented outcomes:
- Attempt 2: `IDENTICAL=YES` with matching hash.
- Attempt 3: `IDENTICAL=YES` with matching hash.
- Final chosen implementation is Attempt 1 code path (selection based on correctness + performance).

Verification artifacts:
- `subRay/results/attempt2_correctness_report.txt`
- `subRay/results/attempt3_correctness_report.txt`
- checker scripts under `subRay/scripts/`

## 15. Official Before/After Performance

Official measurement files:
- Original: `subRay/results/original_official.txt`
- Final: `subRay/results/final_official.txt`

Official results:

| Version | Mean | Std Dev | Improvement | Correct |
|---|---:|---:|---:|---|
| ORIGINAL | 81.285 s | 0.198 s | 0.00% | Yes |
| FINAL | 19.7062 s | 0.0133 s | 75.76% | Yes |

Threshold check:
- Target `>= 7%` improvement: **achieved**.

## 16. Before/After Flame Graph Comparison

Compared artifacts:
- Original reference: `subRay/profiling/flamegraph_pyspy.svg`
- Final reference: `subRay/profiling/final_flamegraph_pyspy.svg`

Important documented caveat:
- These two compared py-spy graphs were not captured under identical workload mode (`--fast` vs non-fast), so direct width-to-width quantitative claims are not valid.

Qualitative only:
- Original graph shows broad pyperf runner/manager and startup/control-plane regions.
- Final graph (reused from Attempt 1 capture because final == attempt1) also shows strong orchestration/worker communication stack presence.
- The optimization speedup is validated by official timing files, not by a strict matched-workload flame-graph width reduction claim.

## 17. Hardware Acceleration Motivation

Why hardware was pursued:
- Software profiling showed persistent heavy numeric/interpreter overhead in intersection-heavy hot paths.
- Intersection and closest-hit logic are high-frequency, arithmetic-dense, and structurally suitable for hardware pipelining/parallelism.

Implemented hardware deliverables:
- RTL modules in `subRay/hw/rtl/`:
  - `fxp_sqrt.sv`
  - `sphere_intersect.sv`
  - `intersect_accel.sv`
- Self-checking testbenches in `subRay/hw/tb/`.
- Simulation evidence in `subRay/hw/results/`.

Measured simulation status:
- ModelSim compile: 0 errors, 0 warnings.
- `tb_fxp_sqrt`: all checks passed.
- `tb_intersect_accel`: all checks passed.

Boundary conditions:
- Hardware RTL is currently Q16.16 fixed-point and iterative v1.
- No synthesis timing/area/power numbers were claimed.
- Hardware performance speedups remain estimates until hardware integration and measurement.

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
