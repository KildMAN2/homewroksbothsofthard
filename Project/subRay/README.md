# Raytrace Benchmark Project

**HWSW Benchmark Optimization, Profiling, and Hardware Acceleration**

This directory contains the complete Raytrace subproject for the HWSW performance-engineering project.

The project starts from the untouched `pyperformance` Raytrace benchmark, profiles the real workload, implements and verifies several software optimizations, compares the original and optimized versions, and then designs and simulates a SystemVerilog accelerator for the repeated intersection/closest-hit work.

The current repository state was reviewed from the latest `master` branch before this README was rewritten.

---

## 1. Project Status

The Raytrace subproject is complete at the software-measurement and RTL-simulation level.

### Official measured software result

| Version | Elapsed Time | Result |
|---|---:|---:|
| Original | `81.285 ± 0.198 s` | baseline |
| Final / Attempt 1 | `19.7062 ± 0.0133 s` | optimized |
| Speedup | `~4.12×` | |
| Runtime improvement | **75.76%** | target achieved |

The course target was at least `7%` improvement.

### Important final-selection note

The repository’s locked official final is **Attempt 1** because the official before/after pipeline and final submission artifacts were produced from it.

Later matched non-fast `perf stat` measurements showed:

| Attempt | Mean |
|---|---:|
| Attempt 1 | `19.7062 ± 0.0133 s` |
| Attempt 2 | `19.68433 ± 0.00708 s` |
| Attempt 3 | `19.6077 ± 0.0171 s` |

Attempt 3 is therefore slightly faster in that later comparison, but Attempt 1 remains the official final artifact. The project does not claim Attempt 1 is fastest in every measurement.

---

## 2. Benchmark Overview

`raytrace` is a pure-Python ray tracer from `pyperformance`.

The timed workload includes:

- camera-ray generation,
- vector and point arithmetic,
- sphere intersections,
- halfspace / plane intersections,
- closest-hit selection,
- recursive reflections,
- shadow / visibility rays,
- Lambert diffuse lighting,
- ambient and specular contributions,
- per-pixel RGB output.

Unlike a native graphics renderer, the cost here is dominated by Python interpreter and object overhead around repeated small geometry operations.

---

## 3. Real Workload Characteristics

Instrumentation of the preserved benchmark shows that one `64 × 64` image involves substantial repeated geometry work.

Important measured properties reported in the final project documentation include:

| Quantity | Value |
|---|---:|
| Rays cast per image | `40,043` |
| Intersection tests per image | `83,694` |
| Temporary `Vector` / `Ray` / `Point` objects | `227,060` |
| Sphere tests ending in the miss path | `96.2%` |

A specific inefficiency found in the visibility path is especially important:

- `_lightIsVisible()` reconstructs the shadow ray inside its per-object loop.
- That behavior accounts for `33,782` of the benchmark’s `40,043` total `Ray()` constructions, about `84%`.

These counts help explain why reducing object creation and method dispatch produces such a large software speedup.

---

## 4. Repository Structure

```text
Project/subRay/
├── README.md
│
├── docs/
│   ├── 00_project_plan.md
│   ├── 01_benchmark_understanding.md
│   ├── 02_pyperformance.md
│   ├── 03_baseline.md
│   ├── 04_perf_profiling.md
│   ├── 05_bottleneck_analysis.md
│   ├── 06_optimization_plan.md
│   ├── 07_optimization_experiments.md
│   ├── 08_hw_sw_interface.md
│   ├── 09_hardware_performance.md
│   └── additional consistency/final-analysis documents
│
├── original/
│   └── bm_raytrace/
│       ├── run_benchmark.py
│       └── pyproject.toml
│
├── optimized/
│   ├── attempt1/
│   ├── attempt2/
│   ├── attempt3/
│   └── final/
│
├── profiling/
│   ├── perf data/reports
│   ├── perf stat outputs
│   ├── suite flame graphs
│   └── supplemental py-spy SVGs
│
├── results/
│   ├── baseline/
│   ├── attempt correctness results
│   ├── original_official.txt
│   └── final_official.txt
│
├── reports/
│   ├── report_raytrace.md
│   ├── report_raytrace.txt
│   ├── baseline_results.txt
│   └── final_performance_comparison.txt
│
├── scripts/
│   ├── script_raytrace.sh
│   ├── run_baseline.sh
│   ├── run_attempt1.sh
│   ├── run_profile.sh
│   ├── run_pmu_profiles_linux.sh
│   ├── generate_flamegraph.sh
│   └── correctness-check scripts
│
├── hw/
│   ├── rtl/
│   │   ├── fxp_sqrt.sv
│   │   ├── sphere_intersect.sv
│   │   └── intersect_accel.sv
│   ├── tb/
│   │   ├── tb_fxp_sqrt.sv
│   │   └── tb_intersect_accel.sv
│   └── results/
│       └── SIMULATION_RESULTS.txt
│
├── prompts/
│   └── AI prompt records
│
└── presentation/
    └── presentation-preparation material
```

---

## 5. Preserved Original Benchmark

The untouched benchmark source is stored under:

```text
Project/subRay/original/bm_raytrace/
```

Important files:

```text
run_benchmark.py
pyproject.toml
```

Optimization work is kept in separate folders.

The project also recorded SHA256 checksums to demonstrate that the original benchmark copy remained unchanged.

---

## 6. Profiling Methodology

Several tools were used because each answers a different question.

### pyperformance / pyperf

Used to execute the benchmark and obtain repeatable timing results and stability information.

### Linux perf

Used for:

- `perf stat`,
- `perf record`,
- `perf report`,
- instruction / branch / cache evidence,
- matched baseline/final sampled call stacks.

### FlameGraph

Generated from perf stack samples for whole-suite baseline/final comparison.

The matched full-suite perf flame graphs are the authoritative visual pair because perf follows the forked benchmark workers.

### py-spy

py-spy flame graphs are preserved as supplemental evidence.

In this project, some py-spy captures mainly observed pyperf manager/import/pipe-wait behavior rather than the actual Raytrace worker kernel because subprocess following was not enabled in those historical captures.

Therefore those particular SVGs are not used as the authoritative source for kernel percentage claims.

---

## 7. Main Profiling Findings

The original profile showed a broad collection of interpreter/object overhead rather than one dominant native function.

Important measured cost families include:

- `_PyEval_EvalFrameDefault`,
- frame creation and destruction,
- `binary_op1`,
- `PyFloat_FromDouble`,
- `PyTuple_GetItem`,
- `_PyObject_GetMethod`,
- `_PyType_Lookup`,
- dictionary/object lookup/deallocation helpers.

Typical `_PyEval_EvalFrameDefault` self-time was roughly in the `20.6%–23.6%` range in baseline profiling captures.

The important conclusion is not that one single Python function dominates, but that repeated geometry arithmetic creates huge interpreter/object overhead.

---

## 8. Software Optimization Attempts

The three Raytrace attempts are separate experiments rather than cumulative mandatory stages.

### Attempt 1 — Scalarization

The primary optimization.

Strategy:

- replace hot-path `Vector`, `Point`, and `Ray` object operations with scalar float locals where possible,
- reduce temporary object construction,
- reduce method dispatch,
- reduce attribute/type lookup,
- simplify hot scene data.

This produced almost all of the software speedup and became the locked official final.

### Attempt 2 — Lookup / Alias Hoisting

Strategy:

- reduce repeated global/helper lookup overhead,
- bind frequently used operations locally inside hot routines.

Correctness remained identical, but the additional speedup over Attempt 1 was very small.

### Attempt 3 — Visibility-Path Inlining

Strategy:

- inline the per-light visibility check in the hot Lambert-lighting path,
- reduce extra function/frame overhead.

It was also correct and measured slightly faster than Attempt 1 in a later non-fast perf-stat run.

---

## 9. Correctness Verification

All software optimization attempts were checked against the preserved original for a fixed `32 × 32` scene.

Recorded result:

```text
IDENTICAL=YES
```

for Attempts 1, 2, and 3.

The checks use deterministic byte comparison / SHA256 reporting.

Important scope boundary:

Exact equality proves correctness for the tested scene and resolution. It does not prove equivalence for every possible camera, scene, resolution, or numeric corner case.

---

## 10. Official Software Performance

Official matched measurements:

```text
Original: 81.285 ± 0.198 s
Final:    19.7062 ± 0.0133 s
```

Calculated:

```text
Speedup ≈ 4.12×
Improvement = 75.76%
```

This exceeds the course target of `7%` by more than an order of magnitude.

---

## 11. Hardware-Counter Evidence

The final matched perf-stat comparison independently supports the wall-clock result.

| Metric | Baseline | Final |
|---|---:|---:|
| Elapsed | `81.285 s` | `~19.667 s` |
| Instructions | `387.3 B` | `99.5 B` |
| Branches | `94.4 B` | `23.7 B` |
| Branch misses | `865.4 M` | `166.2 M` |
| Cache references | `404.9 M` | `198.3 M` |
| Cache misses | `4.29 M` | `2.93 M` |

Approximate reductions reported in the final analysis:

- instructions retired: **74.3% lower**,
- branches: **74.9% lower**,
- branch mispredictions: **80.8% lower**.

That is consistent with removing Python interpreter and dispatch work rather than merely changing memory locality.

---

## 12. Before/After perf Report Interpretation

Authoritative matched suite reports show:

```text
_PyEval_EvalFrameDefault
baseline: ~23.50%
final:    ~27.39%
```

The percentage becomes larger, but this is not a regression.

`perf report` shows **relative share of each run**.

The final execution is roughly four times shorter and executes far fewer instructions and branches. After object/lookup/dictionary/allocation costs are removed, the core interpreter loop becomes a larger fraction of the smaller remaining total.

---

## 13. Hardware Acceleration Candidate

The selected hardware kernel is:

# Sphere / Plane Intersection + Closest-Hit Reduction

The accelerator also supports the visibility / any-hit use case needed for shadow rays.

Why this target was selected:

- intersection testing is repeated extremely frequently,
- each object test is a compact sequence of arithmetic operations,
- object tests are independent,
- closest-hit reduction maps naturally to hardware,
- visibility mode can early-exit on a blocker,
- grouping the full scan behind one accelerator interface is better than offloading one tiny arithmetic operation at a time.

---

## 14. Hardware Architecture

The current RTL is an iterative v1 design using signed **Q16.16 fixed-point** arithmetic.

Implemented RTL:

```text
Project/subRay/hw/rtl/fxp_sqrt.sv
Project/subRay/hw/rtl/sphere_intersect.sv
Project/subRay/hw/rtl/intersect_accel.sv
```

### `fxp_sqrt`

Iterative fixed-point square-root block used by sphere intersection.

### `sphere_intersect`

Implements the sphere-intersection candidate calculation.

### `intersect_accel`

Top-level controller that:

- accepts a ray,
- processes sphere/plane scene objects,
- performs nearest-hit or any-hit/visibility reduction,
- returns hit kind/id/distance.

The current implementation is iterative/shared-unit hardware.

A more aggressive pipelined/multi-lane architecture is discussed only as future work.

---

## 15. Numeric Representation

Software Raytrace uses Python floating-point values.

The RTL prototype uses:

```text
Q16.16 fixed-point
```

This is a deliberate hardware-scope decision.

Advantages:

- substantially simpler RTL than FP64,
- smaller hardware,
- practical for a first accelerator prototype.

Trade-off:

- reduced precision and dynamic range.

Therefore the project does **not** claim bit-exact equivalence between the Q16.16 hardware and the Python floating-point renderer.

The software SHA256 correctness checks apply only to software optimization attempts.

---

## 16. RTL Verification

Simulation tool:

```text
ModelSim Intel FPGA Edition 10.5b
```

Recorded result:

```text
0 compile errors
0 compile warnings
18 / 18 functional checks passed
```

Breakdown:

| Testbench | Checks | Result |
|---|---:|---|
| `tb_fxp_sqrt` | 11 | PASS |
| `tb_intersect_accel` | 7 | PASS |
| **Total** | **18** | **ALL PASS** |

Tests cover:

- zero,
- one,
- non-square roots,
- perfect squares,
- fixed-point scaling,
- direct sphere hit,
- plane-only hit,
- no hit,
- off-axis case,
- blocked visibility,
- clear visibility.

Simulation verifies logical behavior of the RTL against its testbench specification.

---

## 17. HW/SW Boundary

### Implemented

Implemented now:

- direct RTL ports,
- start / busy / done handshake,
- mode selection,
- ray inputs,
- hit outputs,
- Q16.16 datapath,
- simulation testbenches.

### Proposed

Not implemented:

- MMIO register wrapper,
- DMA,
- ray batching,
- Python/C wrapper,
- device driver,
- FPGA runtime integration.

### Why batching matters

The benchmark casts `40,043` rays per image.

If every ray required an expensive CPU↔accelerator transaction, interface overhead could erase much of the compute benefit.

The proposed system therefore uses batched transfers / DMA rather than per-ray software calls.

---

## 18. Hardware Performance Estimates

The project uses an assumed target clock of:

```text
200 MHz
```

This is an **ESTIMATE**, not measured synthesis timing.

Amdahl's Law:

```text
Speedup = 1 / ((1 - P) + P/S)
```

Two documented example scenarios:

### Realistic estimate

```text
P = 0.50
S = 8
Overall ≈ 1.78× over final software
```

### Optimistic estimate

```text
P = 0.70
S = 100
Overall ≈ 3.26× over final software
```

These are estimates only and depend strongly on batching and transfer overhead.

No hardware-in-the-loop timing was performed.

---

## 19. Evidence Boundaries

The project explicitly separates four categories.

### MEASURED SOFTWARE

Examples:

```text
81.285 s → 19.7062 s
75.76% runtime improvement
~4.12× speedup
```

### SIMULATED RTL

Example:

```text
18 / 18 functional checks passed
```

### ESTIMATED HARDWARE

Examples:

```text
200 MHz target
cycles/ray assumptions
Amdahl speedups
area/power/bandwidth projections
```

### PROPOSED SYSTEM INTEGRATION

Examples:

```text
MMIO
DMA
buffering
Python/C wrapper
driver
real FPGA deployment
```

---

## 20. How to Reproduce

Run commands from the repository root.

### First-time setup (install dependencies)

```bash
bash Project/subRay/scripts/script_raytrace.sh setup
```

This detects the OS/package manager and installs the system packages (`python3`, `python3-pip`, `python3-dbg`, `perf`/`linux-tools`, `git`), the Python tools (`pyperformance`, `pyperf`, `py-spy`), and clones FlameGraph into `$HOME/FlameGraph`. Flame-graph generation also detects `/opt/FlameGraph` or a `FLAMEGRAPH_DIR` override.

### Main orchestrator

```bash
bash Project/subRay/scripts/script_raytrace.sh
```

Useful modes:

```bash
bash Project/subRay/scripts/script_raytrace.sh setup
bash Project/subRay/scripts/script_raytrace.sh baseline
bash Project/subRay/scripts/script_raytrace.sh optimize
bash Project/subRay/scripts/script_raytrace.sh profile
bash Project/subRay/scripts/script_raytrace.sh compare
bash Project/subRay/scripts/script_raytrace.sh all
```

### Baseline

```bash
bash Project/subRay/scripts/run_baseline.sh
```

### Attempt 1

```bash
bash Project/subRay/scripts/run_attempt1.sh
```

### Targeted profiling

```bash
PROFILE_TARGET=baseline PROFILE_USE_FAST=0 RUNS=3 \
bash Project/subRay/scripts/run_profile.sh

PROFILE_TARGET=attempt1 PROFILE_USE_FAST=0 RUNS=3 \
bash Project/subRay/scripts/run_profile.sh

PROFILE_TARGET=attempt2 PROFILE_USE_FAST=0 RUNS=3 \
bash Project/subRay/scripts/run_profile.sh

PROFILE_TARGET=attempt3 PROFILE_USE_FAST=0 RUNS=3 \
bash Project/subRay/scripts/run_profile.sh

PROFILE_TARGET=final PROFILE_USE_FAST=0 RUNS=3 \
bash Project/subRay/scripts/run_profile.sh
```

### PMU profiling helper

```bash
bash Project/subRay/scripts/run_pmu_profiles_linux.sh
```

### Flame graph generation

```bash
bash Project/subRay/scripts/generate_flamegraph.sh
```

### Correctness

```bash
python3 Project/subRay/scripts/check_attempt1_correctness.py
python3 Project/subRay/scripts/check_attempt2_correctness.py
python3 Project/subRay/scripts/check_attempt3_correctness.py
```

---

## 21. Main Evidence Files

### Final software comparison

```text
Project/subRay/results/original_official.txt
Project/subRay/results/final_official.txt
Project/subRay/reports/final_performance_comparison.txt
```

### Profiling

```text
Project/subRay/profiling/
```

Important matched suite artifacts include:

```text
perf_report_suite_baseline.txt
perf_report_suite_final.txt
flamegraph_suite_baseline.svg
flamegraph_suite_final.svg
```

### Correctness

```text
Project/subRay/results/attempt1/correctness_report.txt
Project/subRay/results/attempt2_correctness_report.txt
Project/subRay/results/attempt3_correctness_report.txt
```

### Hardware simulation

```text
Project/subRay/hw/results/SIMULATION_RESULTS.txt
```

### Final report

```text
Project/subRay/reports/report_raytrace.md
Project/subRay/reports/report_raytrace.txt
```

### AI prompt record

```text
Project/subRay/prompts/
```

---

## 22. Documentation Reading Order

For the full technical story, read:

1. benchmark understanding,
2. pyperformance / baseline docs,
3. perf profiling,
4. bottleneck analysis,
5. optimization plan / experiments,
6. final software result,
7. before/after profiling,
8. hardware candidate,
9. hardware architecture,
10. RTL implementation and simulation,
11. HW/SW interface,
12. hardware performance estimates,
13. final report.

The consolidated final report is:

```text
Project/subRay/reports/report_raytrace.md
```

---

## 23. Known Limitations

The project does not include:

- synthesis,
- place and route,
- FPGA deployment,
- measured accelerator clock frequency,
- measured area,
- measured power,
- hardware-in-the-loop Raytrace execution,
- implemented MMIO/DMA integration,
- measured end-to-end hardware speedup.

The Q16.16 hardware is also not bit-exact with the Python floating-point implementation.

These limitations are explicitly documented instead of being replaced by guessed numbers.

---

## 24. Key Conclusions

The original Raytrace benchmark spends much of its time executing Python object and interpreter machinery around simple geometry.

The dominant software optimization was therefore not a more advanced ray-tracing algorithm; it was reducing Python-level overhead in the hottest paths.

Scalarization produced the main improvement:

```text
81.285 s → 19.7062 s
75.76% faster
~4.12× speedup
```

The hardware work then targets a different layer: repeated ray/object intersection and hit reduction.

The implemented prototype demonstrates the accelerator logic in SystemVerilog, while real physical hardware integration remains future work.

---

## 25. Companion Benchmark

The second benchmark is:

```text
Project/subPyflate/
```

The two subprojects complement one another:

- **Raytrace:** object-heavy geometry, floating-point math, recursive shading, many intersections.
- **Pyflate:** bit/byte processing, Huffman decoding, MTF/BWT/RLE, tight interpreter loops.

Together they demonstrate two different software bottleneck classes and two different accelerator architectures.
