# Raytrace Benchmark Project (HWSW Optimization + Analysis + Hardware Acceleration)

## 1. Project Overview
This project works on the pyperformance raytrace benchmark and documents the full workflow:
- understand the original benchmark,
- collect profiling evidence,
- identify bottlenecks,
- implement software optimization attempts,
- compare measured performance,
- design and implement a hardware accelerator prototype,
- report measured software and simulated hardware evidence with clear estimate boundaries.

Benchmark source context:
- The benchmark is raytrace from pyperformance.

## 2. Repository Structure
- docs/: step-by-step project documentation (understanding, profiling, optimization, hardware candidate, architecture, interface, performance estimate).
- original/: preserved original benchmark source copy.
- optimized/: software variants (attempt1, attempt2, attempt3) and final selected implementation folder.
- profiling/: perf data, perf reports/stats, and flame graph artifacts (including py-spy SVG outputs).
- results/: stored benchmark and correctness result artifacts, including official original/final timing files.
- reports/: consolidated report files and summary comparison files.
- scripts/: runnable workflow scripts for baseline, attempt runs, profiling, flame graph generation, and correctness checks.
- hw/: hardware RTL, testbenches, and simulation result artifacts.
- prompts/: AI prompt notes used during project work.
- presentation/: presentation preparation material.

## 3. Original Benchmark
Original preserved source:
- subRay/original/bm_raytrace/run_benchmark.py
- subRay/original/bm_raytrace/pyproject.toml

The original source was kept as a preserved reference and optimization work was done in separate folders under optimized/.

## 4. Software Optimization (Attempt 1/2/3/Final)
Implemented software variants:
- optimized/attempt1/
- optimized/attempt2/
- optimized/attempt3/
- optimized/final/

Recorded fast-run means in results files:
- results/attempt1_fast.txt: 103 ms +- 9 ms
- results/attempt2_fast.txt: 242 ms +- 28 ms
- results/attempt3_fast.txt: 243 ms +- 20 ms

Recorded non-fast profiling means in profiling perf_stat files:
- profiling/perf_stat_attempt1.txt: 19.7062 +- 0.0133 s
- profiling/perf_stat_attempt2.txt: 19.68433 +- 0.00708 s
- profiling/perf_stat_attempt3.txt: 19.6077 +- 0.0171 s

Current official final artifact in this repository:
- results/final_official.txt is labeled FINAL OFFICIAL (selected attempt1)
- Command inside that file points to optimized/attempt1/run_benchmark.py

Official measured before/after (from results/original_official.txt and results/final_official.txt):
- ORIGINAL: 81.285 +- 0.198 s
- FINAL: 19.7062 +- 0.0133 s
- Improvement: 75.76%

Correctness artifacts present:
- results/attempt2_correctness_report.txt: IDENTICAL=YES
- results/attempt3_correctness_report.txt: IDENTICAL=YES

## 5. Profiling
Profiling evidence is stored in profiling/ and includes:
- pyperformance/pyperf-run timing artifacts,
- perf sampled call-stack data and reports,
- perf stat counter summaries,
- flame graph artifacts,
- py-spy flame graphs where applicable.

Examples in profiling/:
- perf_report_baseline.txt, perf_report_attempt1.txt, perf_report_attempt2.txt, perf_report_attempt3.txt
- perf_stat_baseline.txt, perf_stat_attempt1.txt, perf_stat_attempt2.txt, perf_stat_attempt3.txt
- flamegraph.svg, flamegraph_original.svg
- flamegraph_pyspy_baseline.svg, flamegraph_pyspy_attempt1.svg, flamegraph_pyspy_attempt2.svg, flamegraph_pyspy_attempt3.svg, flamegraph_pyspy_final.svg

## 6. Hardware Acceleration
Selected accelerator kernel scope:
- ray/object intersection,
- closest-hit reduction,
- visibility blocker logic.

Implemented RTL files:
- hw/rtl/fxp_sqrt.sv
- hw/rtl/sphere_intersect.sv
- hw/rtl/intersect_accel.sv

Verification and evidence:
- hw/tb/tb_fxp_sqrt.sv
- hw/tb/tb_intersect_accel.sv
- hw/results/compile.log
- hw/results/sim_fxp_sqrt.log
- hw/results/sim_intersect_accel.log
- hw/results/SIMULATION_RESULTS.txt

Numeric format in implemented RTL:
- Q16.16 fixed-point.

Measured vs estimated boundary:
- Measured for hardware in this repo: simulation/functional verification results only.
- Estimated (not measured in hardware): future acceleration projections in docs/09_hardware_performance.md.

No claim is made here of synthesis, FPGA deployment, real HW/SW integration runtime, measured area, measured power, or measured hardware speedup.

## 7. How To Reproduce (Existing Scripts)
Run from repository root on a Linux environment with bash, perf, and python3-dbg available.

Main entry point (wrapper/orchestrator):
- bash subRay/scripts/script_raytrace.sh            # defaults to 'all'
- bash subRay/scripts/script_raytrace.sh baseline
- bash subRay/scripts/script_raytrace.sh optimize
- bash subRay/scripts/script_raytrace.sh profile
- bash subRay/scripts/script_raytrace.sh compare
- bash subRay/scripts/script_raytrace.sh all

What script_raytrace.sh compare prints:
- Official original vs final elapsed, computed speedup (~4.1x) and improvement (75.76%).
- Attempt perf_stat elapsed values and the final perf_stat elapsed (profiling/perf_stat_final.txt).
- Baseline vs final perf report hotspots (profiling/perf_report.txt vs profiling/perf_report_final.txt).
- A generated summary file: reports/compare_generated.txt (the curated reports/final_performance_comparison.txt is never overwritten).

Note on perf report percentages:
- perf report shares are relative to each run's samples, not absolute time. `_PyEval_EvalFrameDefault` rises from 20.63% (baseline) to 31.56% (final) because removed overhead shrinks the total, not because it got slower; the speedup is proven by wall-clock time.

Baseline run:
- bash subRay/scripts/run_baseline.sh

Attempt 1 run:
- bash subRay/scripts/run_attempt1.sh

Targeted profiling (baseline/attempt1/attempt2/attempt3/final):
- PROFILE_TARGET=baseline PROFILE_USE_FAST=0 RUNS=3 bash subRay/scripts/run_profile.sh
- PROFILE_TARGET=attempt1 PROFILE_USE_FAST=0 RUNS=3 bash subRay/scripts/run_profile.sh
- PROFILE_TARGET=attempt2 PROFILE_USE_FAST=0 RUNS=3 bash subRay/scripts/run_profile.sh
- PROFILE_TARGET=attempt3 PROFILE_USE_FAST=0 RUNS=3 bash subRay/scripts/run_profile.sh
- PROFILE_TARGET=final PROFILE_USE_FAST=0 RUNS=3 bash subRay/scripts/run_profile.sh

Batch PMU profiling helper:
- bash subRay/scripts/run_pmu_profiles_linux.sh

Generate flame graph from perf.data:
- bash subRay/scripts/generate_flamegraph.sh

Correctness check scripts:
- python3 subRay/scripts/check_attempt1_correctness.py
- python3 subRay/scripts/check_attempt2_correctness.py
- python3 subRay/scripts/check_attempt3_correctness.py

## 8. Main Report
Primary consolidated report:
- subRay/reports/report_raytrace.txt

## 9. AI Prompts
Prompt artifacts:
- subRay/prompts/

## 10. Presentation Material
Presentation prep artifacts:
- subRay/presentation/

## Notes For Course Staff
This repository intentionally keeps measured software results, simulated hardware results, and projected hardware estimates separated:
- Measured software official comparison: results/original_official.txt and results/final_official.txt
- Simulated hardware verification: hw/results/
- Hardware acceleration estimates/planning assumptions: docs/09_hardware_performance.md
