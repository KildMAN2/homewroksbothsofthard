# homewroksbothsofthard

This repository contains two completed HW/SW benchmark projects: benchmark understanding, software optimization, profiling evidence, a proposed/implemented hardware accelerator (RTL + simulation), and final reports.

The two selected, submitted benchmarks are:

- Raytrace (`subRay/`)
- Nbody (`subNbody/`)

## Structure

- `subRay/`: Raytrace benchmark (from pyperformance) — software optimization attempts and final selection, RTL intersection accelerator with self-checking testbenches and ModelSim simulation, perf/py-spy profiling evidence, and consolidated reports.
- `subNbody/`: Nbody benchmark — software optimization (V1 scalarization), RTL accelerator (`nbody_accel_v2.sv`) verified in simulation, perf/flamegraph profiling evidence, and reports.
- `Project/`: VM runbook and planning docs used while running the benchmarks.
- `hw1/`, `hw2/`: earlier coursework directories (not part of the two final benchmark submissions).

## How To Reproduce

The authoritative, per-benchmark instructions live in each sub-project README:

- Raytrace: see `subRay/README.md` (main entry point: `bash subRay/scripts/script_raytrace.sh`).
- Nbody: see `subNbody/README.md`.

Both benchmarks were run in an Ubuntu Jammy VM with `pyperformance`, `perf`, `py-spy`, and FlameGraph available. Always compare original vs final on the same machine with the same flags.

## Final Nbody Submission (summary)

The selected software optimization is V1 scalarization:

- Original: `4.881335 s`
- V1: `4.381726 s`
- Speedup: `1.1140x`
- Improvement: `10.24%`

The final Nbody profiling method is `perf record -F 999 -g`. The final RTL file is `subNbody/hardware/nbody_accel_v2.sv`, functionally verified in simulation only; it was not connected to Python or deployed in hardware, so no measured hardware speedup is claimed. See `subNbody/README.md` for the full Nbody file map, profiling artifacts, and recorded AI prompts.

## Final Raytrace Submission (summary)

The selected final software implementation is under `subRay/optimized/final/`. Official before/after measurement (same host, same methodology):

- Original: `81.285 s`
- Final: `19.7062 s`
- Improvement: `75.76%`

The Raytrace RTL accelerator (`subRay/hw/rtl/`) targets sphere/plane intersection and closest-hit/visibility logic, uses Q16.16 fixed-point, and passes ModelSim simulation. No synthesis, deployment, or measured hardware speedup is claimed. See `subRay/README.md` for full details.

## Hardware Acceleration Deliverables

- Raytrace: `subRay/hw/rtl/` (RTL), `subRay/hw/tb/` (testbenches), `subRay/hw/results/` (simulation evidence).
- Nbody: `subNbody/hardware/nbody_accel_original.sv`, `subNbody/hardware/nbody_accel_v2.sv`.

## Legacy / Exploratory Work (not submitted)

Earlier exploratory nbody + MDP profiling material (previously under `project_results/` and `profiling_step04/`) has been removed and is not part of the final submission. The final Nbody work lives entirely under `subNbody/`.

## Notes

- If VM serial mode truncates long commands, run the provided scripts instead of typing long commands manually.
- Keep VM image files out of git as configured in `.gitignore`.
