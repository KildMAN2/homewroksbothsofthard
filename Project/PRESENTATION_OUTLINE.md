# Presentation Outline (20-25 min + Q&A)

## 1. Benchmark Overview
- Selected benchmarks: nbody and mdp.
- nbody: floating-point pairwise force simulation.
- mdp: harder benchmark with branch-heavy state transitions.

## 2. Profiling Workflow and Evidence
- Nbody final profiling uses `perf record -F 999 -g`.
- Nbody final artifacts are `project_results/nbody/report_original_pdf.txt`, `report_v1_pdf.txt`, `flamegraph_original_pdf.svg`, and `flamegraph_v1_pdf.svg`.
- Older Nbody 499 Hz and earlier 999 Hz files are historical/development artifacts only.
- MDP retains its separate profiling workflow in `project_results/script_mdp.sh`.

## 3. Bottlenecks Identified
- nbody: force accumulation and inverse-distance arithmetic loops.
- mdp: successor expansion, transition aggregation, allocation-heavy loops.

## 4. Optimization Changes and Comparison
- Show Nbody's controlled staged comparison from `subNbody/results/optimization_comparison.txt`; do not use the preliminary `compare.txt` as the final result.
- Nbody final result: `4.881335 s -> 4.381726 s`, `1.1140x`, `10.24%`; V1 scalarization is selected.
- Final profile evidence: `list_subscript` about `1.62% -> 0.01%` and `PyObject_GetItem` about `1.53% -> 0.04%`.
- Use `project_results/mdp/compare.txt` for the separate MDP result.
- Highlight whether each benchmark exceeds 7% improvement target.

## 5. Hardware Accelerator Proposal
- Final Nbody RTL: `subNbody/hardware/nbody_accel_v2.sv`; `nbody_accel_original.sv` is design history only.
- mdp transition score accelerator: `project_results/mdp_transition_accel.sv`.
- Full architecture, interface, and trade-offs:
  - `project_results/HW_ACCELERATOR_PROPOSAL.md`
- Keep evidence categories separate: measured software performance, functionally verified RTL simulation, and proposed HW/SW integration. No Nbody hardware speedup was measured.

## 6. Conclusion
- Summarize software + hardware co-design insights.
- Discuss expected speedup envelope and practical integration constraints.

## Q&A Prep
- Be ready to explain:
  - Why mdp is the hard benchmark.
  - How profiling evidence maps to optimization decisions.
  - Why fixed-point hardware was selected for candidate accelerators.
