# Original Baseline Measurement

**Project:** subRay HWSW Benchmark Optimization, Analysis, and Hardware Acceleration
**Benchmark:** `raytrace`
**Created:** 2026-09-13
**Status:** Planned and pending execution
**Deliverable format:** Markdown only (DOCX not required per user decision 2026-09-13)

## Why Baseline Measurement Is Required

A baseline is the reference point for every later optimization comparison. It provides the original timing distribution, warns about instability, and establishes the exact environment, command, and source version used for the untouched benchmark. Without this measurement, later changes cannot be judged as improvements relative to the original implementation.

Baseline measurement is also required to preserve scientific validity:

- it captures the original benchmark before any optimization,
- it records the exact command and environment,
- it keeps raw stdout/stderr and timing artifacts,
- it exposes warnings about noisy or unstable runs,
- it allows later optimized runs to be compared against the same source and interpreter.

## Exact Benchmark Command

The baseline command runs the untouched original benchmark under `perf` and the debug Python interpreter:

```bash
perf record -F 999 -g -- python3-dbg -m pyperformance run --bench raytrace
```

This matches the style shown in the reference screenshot and keeps the benchmark itself unchanged.

## Environment

The baseline run will be executed inside the Ubuntu 22.04.5 VM already used for discovery.

### Machine / VM Information

- Ubuntu 22.04.5 LTS on QEMU
- 4 virtual CPUs
- 4096 MiB RAM
- QEMU user networking with SSH forwarding on host port 2222
- VM guest hostname: `ubuntu`

### Python Version

- Installed Python minor version: `3.10`
- Exact patch version: to be recorded from the baseline execution environment
- `python3-dbg` availability: to be recorded before or during baseline execution if required by the launcher used

### pyperformance Version

- `pyperformance 1.14.0`

### Original Source Being Used

The untouched benchmark source is the preserved original copy in:

- `subRay/original/bm_raytrace/run_benchmark.py`
- `subRay/original/bm_raytrace/pyproject.toml`

These files were verified byte-for-byte against the VM-installed pyperformance files using SHA256.

## Measurement Methodology

The benchmark is run with pyperformance/pyperf under `perf` so that multiple values are collected rather than a single timing. The methodology is:

1. Run the untouched original benchmark only via `python3-dbg -m pyperformance run --bench raytrace`.
2. Capture environment data before execution.
3. Save stdout and stderr separately.
4. Preserve all warnings, including instability warnings.
5. Record the timing result file produced by the benchmark runner.
6. Save a short human-readable summary.
7. Do not modify any source code.

## Output Files

Planned raw and summary outputs:

- `subRay/results/baseline/`
  - raw stdout
  - raw stderr
  - timing result JSON or equivalent pyperf result artifact
  - any warning transcript
- `subRay/reports/baseline_results.txt`

## Execution Plan

1. Run `subRay/scripts/run_baseline.sh`.
2. Save command output and timing artifacts under `subRay/results/baseline/`.
3. Summarize the mean, standard deviation, min/max if available, number of values, number of runs/processes, warnings, and any unusual behavior.
4. Keep unstable benchmark warnings visible rather than suppressing them.

## Activity Log

### 2026-09-13 - Baseline planning

**Before action:** Create the baseline documentation and the helper script, then run the untouched original benchmark and preserve its outputs.

**Actual outcome:** Pending execution of the perf/python3-dbg command.
