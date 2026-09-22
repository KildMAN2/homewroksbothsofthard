# homewroksbothsofthard

This repository contains two completed HW/SW benchmark projects: benchmark understanding, software optimization, profiling evidence, a proposed/implemented hardware accelerator (RTL + simulation), and final reports.

The two selected, submitted benchmarks are:

- Raytrace (`Project/subRay/`)
- Pyflate (`Project/subPyflate/`)

## Structure

- `Project/subRay/`: Raytrace benchmark (from pyperformance) — software optimization attempts and final selection, RTL intersection accelerator with self-checking testbenches and ModelSim simulation, perf/py-spy profiling evidence, and consolidated reports.
- `Project/subPyflate/`: Pyflate benchmark (from pyperformance) — software optimization attempts and final selection, RTL accelerator with testbenches, perf/py-spy profiling evidence, and consolidated reports.
- `hw1/`, `hw2/`: earlier coursework directories (not part of the two final benchmark submissions).

## How To Reproduce

The authoritative, per-benchmark instructions live in each sub-project README:

- Raytrace: see `Project/subRay/README.md` (main entry point: `bash Project/subRay/scripts/script_raytrace.sh`).
- Pyflate: see `Project/subPyflate/README.md` (main entry point: `bash Project/subPyflate/scripts/script_pyflate.sh`).

Both benchmarks were run in an Ubuntu Jammy VM with `pyperformance`, `perf`, `py-spy`, and FlameGraph available. Always compare original vs final on the same machine with the same flags.

## Final Raytrace Submission (summary)

The selected final software implementation is under `Project/subRay/optimized/final/` (copied from Attempt 1). Official before/after measurement (matched `perf stat` elapsed over three `64x64` executions):

- Original: `81.285 s`
- Final: `19.7062 s`
- Improvement: `75.76%` (speedup ~4.12x)

The Raytrace RTL accelerator (`Project/subRay/hw/rtl/`) targets sphere/plane intersection and closest-hit/visibility logic, uses Q16.16 fixed-point (iterative v1), and passes ModelSim simulation (18/18 checks). No synthesis, deployment, or measured hardware speedup is claimed. See `Project/subRay/README.md` for full details.

## Final Pyflate Submission (summary)

The selected final software implementation is under `Project/subPyflate/optimized/final/` (copy of Attempt 3). Correctness is anchored by the pyflate MD5 gate `afa004a630fe072901b1d9628b960974`.

- VM OFFICIAL (naranja4 QEMU/KVM, python3-dbg 3.10.12): `120.99 s -> 76.307 s`, improvement `+36.93%` (speedup `1.586x`).
- Windows cross-check (pyperformance non-fast, 60 iterations): `516 ms -> 362 ms`, improvement `+29.84%`.

The Pyflate RTL accelerator lives under `Project/subPyflate/hw/rtl/`, verified in simulation only; no synthesis, deployment, or measured hardware speedup is claimed. See `Project/subPyflate/README.md` for full details.

## Hardware Acceleration Deliverables

- Raytrace: `Project/subRay/hw/rtl/` (RTL), `Project/subRay/hw/tb/` (testbenches), `Project/subRay/hw/results/` (simulation evidence).
- Pyflate: `Project/subPyflate/hw/rtl/` (RTL), `Project/subPyflate/hw/tb/` (testbenches), `Project/subPyflate/hw/results/` (simulation evidence).

## Notes

- If VM serial mode truncates long commands, run the provided scripts instead of typing long commands manually.
- Keep VM image files out of git as configured in `.gitignore`.
