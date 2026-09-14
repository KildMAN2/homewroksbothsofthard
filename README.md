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

## Final Nbody Submission

The selected software optimization is V1 scalarization:

- Original: `4.881335 s`
- V1: `4.381726 s`
- Speedup: `1.1140x`
- Improvement: `10.24%`

The final Nbody profiling method is `perf record -F 999 -g`. Use these authoritative artifacts:

- `project_results/nbody/report_original_pdf.txt`
- `project_results/nbody/report_v1_pdf.txt`
- `project_results/nbody/flamegraph_original_pdf.svg`
- `project_results/nbody/flamegraph_v1_pdf.svg`

Older Nbody profiling files are retained as historical/development artifacts. The final profile shows `list_subscript` at about `1.62% -> 0.01%` and `PyObject_GetItem` at about `1.53% -> 0.04%`, consistent with reduced repeated Python list-access overhead.

The final RTL file is `subNbody/hardware/nbody_accel_v2.sv`, functionally verified in simulation. It was not connected to Python or deployed in hardware, so no measured hardware speedup is claimed. See `subNbody/README.md` for the Nbody file map and `project_results/prompt.txt` for the recorded AI prompts.

## Hardware acceleration deliverables

See:

- `subNbody/hardware/nbody_accel_original.sv`
- `subNbody/hardware/nbody_accel_v2.sv`
- `project_results/mdp_transition_accel.sv`
- `project_results/HW_ACCELERATOR_PROPOSAL.md`

## Notes

- If VM serial mode truncates long commands, run the scripts instead of manual long commands.
- Keep VM image files out of git as configured in `.gitignore`.
