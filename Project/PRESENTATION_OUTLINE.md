# Presentation Outline (20-25 min + Q&A)

## 1. Benchmark Overview
- Selected benchmarks: nbody and mdp.
- nbody: floating-point pairwise force simulation.
- mdp: harder benchmark with branch-heavy state transitions.

## 2. Profiling Workflow and Evidence
- Collected baseline JSON outputs in `project_results/`.
- Used perf collection and FlameGraph generation workflow from:
  - `project_results/script_nbody.sh`
  - `project_results/script_mdp.sh`
- Artifacts per benchmark:
  - `perf.data`
  - `report.txt`
  - `flamegraph_*.svg`

## 3. Bottlenecks Identified
- nbody: force accumulation and inverse-distance arithmetic loops.
- mdp: successor expansion, transition aggregation, allocation-heavy loops.

## 4. Optimization Changes and Comparison
- Show baseline vs optimized means with compare output:
  - `project_results/nbody/compare.txt`
  - `project_results/mdp/compare.txt`
- Highlight whether each benchmark exceeds 7% improvement target.

## 5. Hardware Accelerator Proposal
- nbody arithmetic accelerator: `project_results/nbody_accel.sv`.
- mdp transition score accelerator: `project_results/mdp_transition_accel.sv`.
- Full architecture, interface, and trade-offs:
  - `project_results/HW_ACCELERATOR_PROPOSAL.md`

## 6. Conclusion
- Summarize software + hardware co-design insights.
- Discuss expected speedup envelope and practical integration constraints.

## Q&A Prep
- Be ready to explain:
  - Why mdp is the hard benchmark.
  - How profiling evidence maps to optimization decisions.
  - Why fixed-point hardware was selected for candidate accelerators.
