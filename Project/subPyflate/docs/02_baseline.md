# Pyflate — Baseline

## Purpose

Establish the untouched-original wall-clock cost of the pyflate benchmark, so
every later optimization can be compared to a known point. Baseline is
measured by running the preserved original benchmark from
`Project/subPyflate/original/bm_pyflate/` under pyperformance.

## Environment

To be captured on the VM by `Project/subPyflate/scripts/run_baseline.sh`:

| Field | Value |
|---|---|
| OS | TO BE COLLECTED IN VM (`uname -a`) |
| Kernel | TO BE COLLECTED IN VM (`uname -r`) |
| CPU | TO BE COLLECTED IN VM (`lscpu \| head`) |
| python3-dbg | TO BE COLLECTED IN VM (`python3-dbg --version`) |
| pyperformance | TO BE COLLECTED IN VM (`pyperformance --version`) |
| perf | TO BE COLLECTED IN VM (`perf --version`) |

The script writes `results/baseline/environment.txt` with these values before
running.

## Baseline Command

Primary (official baseline):

```
python3-dbg -m pyperformance run --bench pyflate
```

Repeated under `perf stat` so we get both a pyperf mean/std-dev and an
independent `seconds time elapsed` figure:

```
perf stat -r 3 -- python3-dbg -m pyperformance run --bench pyflate
```

Cheap development run for iteration (fast mode):

```
python3-dbg -m pyperformance run --bench pyflate --fast
```

All three commands operate on the untouched benchmark under `original/`. No
source is modified.

## Correctness

The benchmark itself asserts `md5(out) == "afa004a630fe072901b1d9628b960974"`
after every decompression. If the run completes without raising
`MD5 checksum mismatch`, correctness is proven for the actual measurement.

## Preliminary Timing (fast mode)

`TO BE COLLECTED IN VM` — the runner script writes it here and to
`results/baseline/stdout.txt`.

| Field | Value |
|---|---|
| Command | `python3-dbg -m pyperformance run --bench pyflate --fast` |
| Mean | TO BE COLLECTED IN VM |
| Std dev | TO BE COLLECTED IN VM |
| Warnings | TO BE COLLECTED IN VM |

## Official Timing

`TO BE COLLECTED IN VM`.

| Field | Value |
|---|---|
| Command | `python3-dbg -m pyperformance run --bench pyflate` |
| Mean | TO BE COLLECTED IN VM |
| Std dev | TO BE COLLECTED IN VM |
| Min | TO BE COLLECTED IN VM |
| Max | TO BE COLLECTED IN VM |
| Runs (values) | TO BE COLLECTED IN VM |
| Processes | TO BE COLLECTED IN VM |
| Warmups | TO BE COLLECTED IN VM |
| Stability warnings | TO BE COLLECTED IN VM |

`perf stat -r 3` (independent stopwatch):

| Field | Value |
|---|---|
| `seconds time elapsed` (mean of 3) | TO BE COLLECTED IN VM |
| cpu-clock | TO BE COLLECTED IN VM |
| instructions | TO BE COLLECTED IN VM |
| branches / branch-misses | TO BE COLLECTED IN VM |
| cache-references / cache-misses | TO BE COLLECTED IN VM |

## Summary Table (filled after collection)

| Version | Measurement | Mean | Std Dev | Runs | Command |
|---|---|---|---|---|---|
| Original (preliminary) | pyperformance --fast | TBD | TBD | TBD | `... --bench pyflate --fast` |
| Original (official) | pyperformance | TBD | TBD | TBD | `... --bench pyflate` |
| Original (perf stat -r 3) | perf stat elapsed | TBD | TBD | 3 | `perf stat -r 3 -- ...` |

## Baseline Observations (placeholder)

Fill in after the VM run:
- Is the benchmark stable? (pyperformance prints stability warnings when
  std-dev is large; the raytrace baseline had exactly this problem.)
- Is the environment noisy? (background load, CPU governor, thermal throttle)
- Does `perf stat` cycles/instructions show sensible IPC?

Any warning printed by pyperformance is preserved verbatim in
`results/baseline/stdout.txt` and `results/baseline/stderr.txt`.
