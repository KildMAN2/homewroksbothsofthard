# How pyperformance Executes the raytrace Benchmark

**Project:** subRay HWSW Benchmark Optimization, Analysis, and Hardware Acceleration
**Benchmark:** `raytrace` (resolved earlier from the `<BENCHMARK>` placeholder)
**Created:** 2026-09-13
**Status:** Completed (two environment facts remain to verify before profiling; see Limitations)
**Deliverable format:** Markdown only (DOCX not required per user decision 2026-09-13)
**Constraints for this step:** Read-only informational commands only. No benchmark timing run. No optimization. No source modification.

## Purpose of This Step

Document how pyperformance discovers and executes the `raytrace` benchmark and define the statistical vocabulary pyperf uses (loops, values, processes, warmups, repetitions, mean, standard deviation, stability). This step does not measure baseline performance; that is a later requirement.

## Plan Before Experiments

1. Record the installed CPython version in the VM.
2. Check whether a debug interpreter (`python3-dbg`) is available.
3. Record the installed pyperformance version.
4. Confirm the exact benchmark identifier.
5. Record how to list benchmarks and how to run this specific benchmark.
6. Define pyperf's measurement concepts.
7. Save every command executed and its raw output under `Project/subRay/logs/`.
8. Update this document with verified facts and stop.

## Environment Facts (VM-Verified)

Per user decision, this step reuses only VM output already captured earlier today; the raw evidence is consolidated in `Project/subRay/logs/02_pyperformance_env.txt` (originally captured in `Project/subRay/logs/01_vm_discovery.txt`). No new VM commands were executed for this step.

- **Installed Python version:** minor version **3.10**, verified indirectly from the installed benchmark tree path `/usr/local/lib/python3.10/dist-packages/...` and the launcher shebang `#!/usr/bin/python3`. The exact patch level (e.g. `3.10.x`) was **not captured this session** and is listed under Limitations.
- **python3-dbg availability:** **NOT VERIFIED THIS SESSION.** A debug interpreter is required for the later profiling step and must be confirmed then; it was not part of this session's captured output, so no claim is made here.
- **pyperformance version:** **1.14.0** (`pyperformance --version` -> `pyperformance 1.14.0`).
- **Exact benchmark identifier:** **`raytrace`**, confirmed by `pyperformance list` (`- raytrace`), the suite `MANIFEST` (`raytrace     <local>`), and `bm_raytrace/pyproject.toml` (`[tool.pyperformance] name = "raytrace"`).

## How to List Benchmarks

The suite lists all registered benchmarks with:

```bash
pyperformance list
```

To confirm the target benchmark specifically (raw output captured this session):

```bash
pyperformance list | grep -i ray
# - raytrace
```

## How to Run This Benchmark

The documented, non-optimizing command to run only this benchmark is:

```bash
pyperformance run --benchmarks raytrace -o Project/subRay/results/baseline_raytrace.json
```

- `--benchmarks raytrace` selects only the `raytrace` benchmark.
- `-o <file>` writes the pyperf result (values, mean, standard deviation, metadata) to JSON for later comparison.

This command was **not executed in this step**. Running it and saving its raw output is the separate baseline-performance requirement and will be done under that step, not here.

## Measurement Concepts

These are standard definitions of how pyperf (used by pyperformance via `bench_time_func`) structures a measurement. They are documentation, not measured results.

### Loops

An inner repeat count. pyperf calls the timed function with a `loops` value and the function runs its workload `loops` times inside a single timed span. pyperf calibrates `loops` automatically so each timed span is long enough to dominate timer resolution and per-call overhead. Reported per-value time is divided by `loops` to yield the time of a single workload iteration. For `raytrace`, one loop iteration is one full scene construction plus render.

### Values

A value is one recorded sample: the time of one timed span divided by its `loops`. Multiple values are collected so the result is a distribution, not a single reading.

### Processes

pyperf runs the benchmark in several independent worker processes. Each worker starts a fresh interpreter, reducing the influence of one process's warmup state, memory layout, or transient system conditions. Values from all worker processes are aggregated.

### Warmups

Initial iterations whose timings are discarded. They let CPU caches, branch predictors, interpreter state, and memory allocation reach a steadier regime before values are recorded, so warmups are excluded from the reported statistics.

### Repetitions

The overall number of recorded values across processes (values per process multiplied by the number of processes). More repetitions give a more reliable estimate of the underlying distribution.

### Mean

The arithmetic average of the recorded values. It is the primary central-tendency estimate pyperf reports for the benchmark.

### Standard Deviation

A measure of spread of the recorded values around the mean. A small standard deviation relative to the mean indicates repeatable measurements; a large one indicates noisy measurements.

### Benchmark Stability

Stability describes how consistent the values are across loops and processes. pyperf emits warnings (for example, when the standard deviation is large relative to the mean) to flag unstable results. On a shared or virtualized host, scheduler jitter and noisy neighbors reduce stability, so single readings can be misleading.

### Why Benchmarking Must Use Multiple Measurements

A single timing conflates the workload with transient noise (scheduling, cache state, frequency scaling, other processes). Collecting many values across multiple processes and reporting mean and standard deviation separates the signal from the noise, exposes instability through spread, and makes before/after comparisons defensible instead of anecdotal. Any later comparison of the original versus an optimized version in this project must be based on these aggregated statistics, not a single run.

## Warnings, Errors, and Limitations

- This step intentionally does not run a timing measurement; no performance numbers are reported here.
- Long serial-console commands may be truncated in this VM; short commands are used and any truncated/cancelled attempts are preserved in the log.
- **python3 exact patch version is NOT VERIFIED this session.** Only the minor version `3.10` is established (from the install path and launcher). Confirm with `python3 --version` before profiling.
- **python3-dbg availability is NOT VERIFIED this session.** Confirm with `which python3-dbg` and `python3-dbg --version` before profiling, since the profiling step depends on a debug interpreter.
- Per user decision, no new VM commands were executed for this step; facts were taken only from output already captured earlier today.

## Activity Log

### 2026-09-13 - pyperformance analysis initialized

**Before action:** Create this Markdown source of truth, run read-only version/availability/list commands in the VM, and save raw outputs. Do not run the benchmark and do not optimize.

**Actual outcome:** The interactive handle to the QEMU serial console was unavailable this turn. On the user's instruction, the step was completed using only VM output already captured earlier today (consolidated in `Project/subRay/logs/02_pyperformance_env.txt`). Verified: pyperformance `1.14.0`, benchmark id `raytrace`, interpreter minor `3.10`, `/usr/bin/python3` launcher. Left unverified (recorded honestly, not guessed): python3 exact patch version and python3-dbg availability. No benchmark run, no optimization, no source change.
