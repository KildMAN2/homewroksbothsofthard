# homewroksbothsofthard

This repository contains HW benchmarking and optimization artifacts, including reproducible scripts, profiling evidence, and hardware-acceleration proposals.

## Structure

- `Project/`: planning and VM runbook docs
- `project_results/`: benchmark outputs, perf/flamegraph scripts, reports, and HDL proposals
- `profiling_step04/`: earlier profiling artifact set
- `hw1/`, `hw2/`: coursework directories

## Reproduce nbody + mdp workflow

Run inside Ubuntu Jammy VM with `pyperformance`, `perf`, and FlameGraph installed:

1. `cd /root/homewroksbothsofthard/project_results`
2. `bash script_nbody.sh`
3. `bash script_mdp.sh`

Generated outputs include:

- baseline and optimized JSON files
- `perf.data`, `report.txt`, `out.perf`, `out.folded`
- `flamegraph_*.svg`
- `*_compare.txt`
- `report_*.txt`

## Hardware acceleration deliverables

See:

- `subNbody/hardware/nbody_accel_original.sv`
- `project_results/mdp_transition_accel.sv`
- `project_results/HW_ACCELERATOR_PROPOSAL.md`

## Notes

- If VM serial mode truncates long commands, run the scripts instead of manual long commands.
- Keep VM image files out of git as configured in `.gitignore`.
