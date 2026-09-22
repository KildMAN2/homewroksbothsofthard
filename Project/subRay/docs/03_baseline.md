# Original Baseline Measurement

**Project:** subRay HWSW Benchmark Optimization, Analysis, and Hardware Acceleration
**Benchmark:** `raytrace`
**Created:** 2026-09-13
**Status:** Completed
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

The baseline run was executed inside the Ubuntu 22.04.5 VM already used for discovery.

### Machine / VM Information

- Ubuntu 22.04.5 LTS on QEMU
- 4 virtual CPUs
- 4096 MiB RAM
- QEMU user networking with SSH forwarding on host port 2222
- VM guest hostname: `ubuntu`

### Python Version

- Installed Python version: `Python 3.10.12`
- `python3-dbg` availability: available at `/usr/bin/python3-dbg`
- `python3-dbg` version: `Python 3.10.12`

### pyperformance Version

- `pyperformance 1.14.0`

### Original Source Being Used

The untouched benchmark source is the preserved original copy in:

- `Project/subRay/original/bm_raytrace/run_benchmark.py`
- `Project/subRay/original/bm_raytrace/pyproject.toml`

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

Produced raw and summary outputs:

- `Project/subRay/results/baseline/`
  - `environment.txt`
  - `perf_stdout.txt`
  - `perf_stderr.txt`
  - `stdout.txt` and `stderr.txt` from an earlier interrupted pre-final attempt
  - local-only perf data artifacts not committed to GitHub
- `Project/subRay/reports/baseline_results.txt`

## Execution Plan

1. Run `Project/subRay/scripts/run_baseline.sh`.
2. Save command output and timing artifacts under `Project/subRay/results/baseline/`.
3. Summarize the mean, standard deviation, min/max if available, number of values, number of runs/processes, warnings, and any unusual behavior.
4. Keep unstable benchmark warnings visible rather than suppressing them.

## Measured Result

- **Exact command:** `perf record -F 999 -g -o /root/homewroksbothsofthard/Project/subRay/results/baseline/perf.data -- python3-dbg -m pyperformance run --bench raytrace`
- **Mean:** `26.8 sec`
- **Standard deviation:** `5.7 sec` (more precisely `5.67 sec` in the warning text)
- **Maximum:** `48.7 sec`
- **Minimum:** not reported in the saved output
- **Observed progress dots in successful stdout:** `21`
- **Benchmark cases:** `(1/1) raytrace`
- **Worker-process count:** not explicitly reported in the saved output
- **Number of values:** not explicitly reported by the saved text; only `21` progress dots are observable in `perf_stdout.txt`
- **Start time:** `2026-09-13 03:27:16.851154`
- **End time:** `2026-09-13 04:05:13.373690`
- **Approximate wall-clock duration:** about `37 min 56.5 sec`

## Warnings and Unusual Behavior

Preserved exactly from the successful final run:

- `WARNING: the benchmark result may be unstable`
- `* the standard deviation (5.67 sec) is 21% of the mean (26.8 sec)`
- `* the maximum (48.7 sec) is 81% greater than the mean (26.8 sec)`
- `Couldn't record kernel reference relocation symbol`
- `Symbol resolution may be skewed if relocation was used (e.g. kexec).`
- `Check /proc/kallsyms permission or run as root.`
- `perf_event__synthesize_bpf_events: failed to synthesize bpf images: No such file or directory`
- `Couldn't synthesize bpf events.`
- repeated `distutils` deprecation warnings emitted during virtual-environment package operations

Other preserved behavior:

- An earlier non-final attempt was interrupted and remains saved in `Project/subRay/results/baseline/stdout.txt`.
- The final successful attempt exited with status `0` and is recorded in `Project/subRay/logs/03_baseline_run.log`.
- Large perf binary artifacts were kept locally in the VM/host workspace but intentionally excluded from the GitHub push to avoid another transport failure.

## Activity Log

### 2026-09-13 - Baseline planning

**Before action:** Create the baseline documentation and the helper script, then run the untouched original benchmark and preserve its outputs.

**Actual outcome:** Completed successfully. The final run used `perf record -F 999 -g -- python3-dbg -m pyperformance run --bench raytrace`, exited with status `0`, and produced a baseline result of `26.8 sec +- 5.7 sec`. The saved output explicitly warns that the benchmark may be unstable.
