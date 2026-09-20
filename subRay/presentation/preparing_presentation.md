# Raytrace Presentation Preparation (20-25 Minutes)

## Slide 1 — Project Goal

### Show
Project title, course context, and one-line objective: optimize pyperformance Raytrace and design a hardware accelerator path.

### Say
This project had two goals. First, improve Raytrace software performance with correctness preserved. Second, design and validate a hardware accelerator prototype for the most suitable kernel. I kept all measurements evidence-based and separated measured results from estimates.

### Key Point
The project is both software optimization and hardware acceleration planning, with strict evidence control.

### Likely Question
What success metric did you target?

### Answer
Primary software metric was before/after benchmark runtime improvement with correctness retained. Final measured software improvement was 75.76%.

## Slide 2 — What Raytrace Does

### Show
Simple diagram: camera rays, sphere/plane intersections, shading, shadows, recursion, pixel output.

### Say
Raytrace generates a ray per pixel, finds intersections with scene objects, computes shading with ambient, Lambert diffuse, and specular reflection, checks shadows by casting light rays, and writes RGB output.

### Key Point
Work is dominated by repeated per-pixel and per-ray geometric evaluation.

### Likely Question
Is this a synthetic benchmark or realistic workload?

### Answer
It is a pyperformance benchmark, so it is synthetic but representative of Python-heavy geometric and object-oriented workload behavior.

## Slide 3 — Original Algorithm

### Show
Step list: generate ray -> intersect all objects -> choose nearest hit -> shade -> recurse -> write pixel.

### Say
The original implementation is object-heavy. It creates many Vector, Point, and Ray objects and repeatedly calls methods in hot loops. It also builds per-ray intersection lists and does visibility scans per light.

### Key Point
Algorithmic structure is standard, but Python object and dispatch overhead is large.

### Likely Question
Did you change asymptotic complexity?

### Answer
No. Improvements were constant-factor reductions in Python overhead, not big-O changes.

## Slide 4 — Baseline

### Show
Two boxes: early baseline summary and final official baseline summary.

### Say
I kept all baseline evidence. Early baseline run in VM showed 26.8 s mean with high instability warning. Final official baseline for the original script was 81.285 s ± 0.198 s with perf-stat stability reported in the saved artifact.

### Key Point
Use official before/after files for final comparison; keep earlier noisy baseline as historical evidence.

### Likely Question
Why are there two baseline-style numbers?

### Answer
They come from different runs/stages. The official comparison uses dedicated original_official and final_official artifacts.

## Slide 5 — Profiling Methodology

### Show
Three-column table: pyperformance, perf, py-spy.

### Say
I used pyperformance for benchmark statistics, perf for sampled hotspot evidence and counters, and py-spy for readable Python flame graphs. I did not rerun expensive profiling unnecessarily and preserved all raw artifacts.

### Key Point
Methods are complementary: timing, sampled low-level hotspots, and readable Python call stacks.

### Likely Question
Why not rely on only perf?

### Answer
perf is essential but can be harder to interpret in Python-heavy contexts. py-spy adds readable Python stack context.

## Slide 6 — perf Results

### Show
Hotspot family list from saved perf reports with percentages.

### Say
The strongest perf families were interpreter and runtime overhead: _PyEval_EvalFrameDefault around 20.6% to 23.6%, plus frame creation/deallocation, binary_op1, float boxing, tuple access, and lookup paths.

### Key Point
Measured bottlenecks are mostly Python execution overhead and repeated scalar arithmetic effects.

### Likely Question
Did perf isolate one C math kernel?

### Answer
No. Because this is pure Python, the cost appears through interpreter/runtime symbols rather than one isolated native kernel.

## Slide 7 — py-spy Flame Graph

### Show
Baseline py-spy flame graph screenshot with annotation: width = runtime contribution, height = call-stack depth.

### Say
In flame graphs, width shows how much sampled runtime a stack contributes. Height shows stack depth, not time. Baseline py-spy showed broad pyperf orchestration and benchmark call paths. It complements perf by making Python stacks easier to read.

### Key Point
Flame-graph width is the core hotspot cue; height is structural depth.

### Likely Question
Can you compare widths as exact percentages?

### Answer
Only if sample context is equivalent and supported by data; I used qualitative comparison and perf text for exact percentages.

## Slide 8 — Main Bottleneck

### Show
Single statement: Python interpreter/runtime overhead triggered by repeated intersection/shading loops.

### Say
The main bottleneck is not one algorithmic bug but cumulative Python overhead from hot geometric loops: dispatch, frame churn, lookup, and numeric boxing.

### Key Point
Optimization should reduce Python-level work per ray/pixel.

### Likely Question
So was the bottleneck compute or language runtime?

### Answer
Both interact, but measured evidence points strongly to runtime overhead driven by frequent geometric computations.

## Slide 9 — Optimization Candidates

### Show
Ranked list of candidates from planning doc.

### Say
Candidates were ranked from measured evidence: scalarize geometry path, remove temporary intersection structures, hoist lookups, and other smaller refinements. Hardware candidate selection was handled separately.

### Key Point
Candidate ranking was evidence-based, not arbitrary.

### Likely Question
How did you avoid overfitting to one profile run?

### Answer
I used multiple saved profiling artifacts and only accepted changes with correctness and benchmark evidence.

## Slide 10 — Attempt 1

### Show
Attempt 1 summary: scalar float locals + tuple scene data.

### Say
Attempt 1 rewrote the hottest object-heavy path to scalar locals and tuple-based structures while preserving behavior. This directly targeted measured overhead families.

### Key Point
Attempt 1 attacked the biggest measured constant costs.

### Likely Question
Why is scalarization effective in Python?

### Answer
It reduces object allocation, method dispatch, and repeated attribute/lookup overhead in inner loops.

## Slide 11 — Attempts 2 and 3

### Show
Table: Attempt 2 and 3 strategy + result.

### Say
Attempt 2 hoisted hot helper/global lookups. Attempt 3 inlined visibility logic in the Lambert loop. Both were correctness-validated. In the later non-fast perf stat comparison the three attempts were within about 0.5% of each other, and Attempt 3 was actually slightly faster than Attempt 1.

### Key Point
Attempts 2 and 3 are marginal variants; Attempt 1 remains the locked official final.

### Likely Question
Were attempts 2 and 3 failures?

### Answer
No. They were correctness-valid. Attempt 1 remains the locked official final because the official result and submission pipeline were produced from it, even though Attempt 3 was slightly faster in the later perf stat.

## Slide 12 — Why Attempt 1 Is the Official Final

### Show
Non-fast perf stat means:
Attempt 1: 19.7062 s, Attempt 2: 19.68433 s, Attempt 3: 19.6077 s.

### Say
Attempt 1 introduced the main scalarization optimization and produced almost the entire software speedup. It is the locked official final because the official before/after result and the final submission pipeline were generated from Attempt 1. Attempt 3 was slightly faster in the later non-fast perf stat comparison, but it is not the locked official final.

### Key Point
Attempt 1 is the official final; it is not claimed to be the fastest in every measurement.

### Likely Question
Why not pick the slightly faster Attempt 3?

### Answer
The official result and submission pipeline were locked to Attempt 1; Attempt 3's small perf stat edge was not re-locked as the official final.

## Slide 13 — Correctness Verification

### Show
Checksum comparison concept and IDENTICAL=YES outputs for attempts 1, 2, and 3.

### Say
Correctness checks compared deterministic outputs and SHA256 hashes at a fixed 32x32 scene. All three attempts show IDENTICAL=YES in saved reports (Attempt 1: results/attempt1/correctness_report.txt). Exact byte/hash equality proves correctness for the tested fixed scene and resolution, not for every possible input.

### Key Point
Performance gains were accepted only with correctness preserved.

### Likely Question
Did you accept approximate visual correctness?

### Answer
No. The checks used deterministic output comparison and hash-based evidence.

## Slide 14 — Official Before/After Results

### Show
Official table:
Original 81.285 s ± 0.198 s
Final 19.7062 s ± 0.0133 s

### Say
These official values come from saved project result artifacts and use the same methodology/environment for direct comparison.

### Key Point
Official comparison is the authoritative software outcome.

### Likely Question
What about benchmark stability?

### Answer
Official artifacts include stability information from perf stat: approximately ±0.24% original and ±0.07% final.

## Slide 15 — 75.76% Improvement

### Show
Equation and final number.
Improvement = (81.285 - 19.7062) / 81.285 * 100 = 75.76%.

### Say
The final software improvement is 75.76%, which clearly exceeds the 7% requirement.

### Key Point
Software objective was met by a large margin.

### Likely Question
Is that measured or estimated?

### Answer
Measured software performance from official result files.

## Slide 16 — Hardware Acceleration Motivation

### Show
Bridge slide from software bottleneck to hardware candidate.

### Say
Even after software optimization, intersection-heavy numeric work remains high-frequency. That made hardware acceleration of the intersection/closest-hit kernel a rational next step.

### Key Point
Hardware target was chosen from hotspot behavior and operation structure.

### Likely Question
Why not accelerate all shading in hardware?

### Answer
Full shading/recursion control is more complex and less modular. Intersection kernel gives a cleaner first boundary.

## Slide 17 — Selected Hardware Kernel

### Show
Kernel definition:
Sphere/plane intersection + nearest-hit reduction + visibility blocker check.

### Say
The selected kernel is repeated many times per shaded point and has clear arithmetic structure: dot products, discriminant, sqrt, comparisons, and min-reduction.

### Key Point
Chosen kernel maximizes repeatable arithmetic per control overhead.

### Likely Question
Why not choose normalize/reflect first?

### Answer
Useful, but narrower impact if intersection scan remains in software.

## Slide 18 — Accelerator Architecture

### Show
Top architecture blocks: interface, input buffer, intersection datapath, reduction, output.

### Say
The architecture separates arithmetic-heavy intersection processing in hardware and leaves scene setup, recursion, and final shading composition in software.

### Key Point
Clear hardware/software partition reduces integration risk.

### Likely Question
Is this architecture measured on FPGA?

### Answer
No. Architecture performance is estimated; only RTL simulation is measured.

## Slide 19 — Datapath

### Show
Datapath math sequence:
CP = C - P, v = dot(CP,D), cp2 = dot(CP,CP), disc = r^2 - (cp2 - v^2), t = v - sqrt(disc), min-reduction.

### Say
Datapath is arithmetic-forward and suitable for pipelining. Plane intersection uses projection and reciprocal path. Visibility mode checks blocker existence with threshold logic.

### Key Point
Datapath operations are deterministic and hardware-friendly.

### Likely Question
What numeric format was implemented?

### Answer
Implemented RTL uses signed fixed-point Q16.16 for practical synthesizable v1.

## Slide 20 — Control / Pipeline

### Show
FSM states and stage concept.

### Say
Control uses start/busy/done sequencing and iterative sphere processing in v1 RTL. Planned future architecture includes deeper pipelining and multiple lanes; current implemented v1 prioritizes correctness and completeness.

### Key Point
Current RTL is functionally complete but not the final high-throughput microarchitecture.

### Likely Question
Did you implement multi-lane pipelining now?

### Answer
No. Multi-lane high-throughput design is proposed; implemented RTL is iterative v1.

## Slide 21 — SystemVerilog Implementation

### Show
Module hierarchy:
intersect_accel, sphere_intersect, fxp_sqrt.

### Say
I implemented three SystemVerilog modules with parameterization and clear boundaries. fxp_sqrt is iterative, sphere_intersect computes candidate t, and intersect_accel controls scene iteration and result reduction.

### Key Point
RTL is real implementation, not pseudo code.

### Likely Question
Is it synthesizable?

### Answer
Yes, designed as synthesizable RTL where appropriate; no fake placeholder logic.

## Slide 22 — Simulation Results

### Show
ModelSim result summary:
compile errors 0, warnings 0;
SQRT TB pass;
ACCEL TB pass.

### Say
Simulation was actually run in ModelSim Intel FPGA Edition 10.5b. Both testbenches passed all checks, including direct hits, plane-only hit, no-hit, off-axis case, and visibility blocked/clear cases.

### Key Point
RTL behavior is validated in simulation.

### Likely Question
Did you measure FPGA speedup?

### Answer
No. Simulation validates logic correctness, not deployed hardware performance.

## Slide 23 — HW/SW Interface

### Show
Implemented vs Proposed split:
Implemented: RTL port-level handshake.
Proposed: MMIO registers, buffers, DMA, Python wrapper/driver.

### Say
Today, interface is testbench-driven RTL ports. For deployment, we need a native wrapper/driver, register map, and likely batching/DMA so transfer overhead does not erase compute gains.

### Key Point
Integration path is defined, but system-level deployment is not yet implemented.

### Likely Question
Why does communication overhead matter so much?

### Answer
Per-ray unbatched transfers can be comparable to or larger than compute time, so batching is essential.

## Slide 24 — Estimated Hardware Performance and Tradeoffs

### Show
Amdahl equation and optimistic/realistic estimates.

### Say
Using Amdahl's Law with clearly labeled assumptions:
Speedup = 1 / ((1 - P) + P/S).
Estimated optimistic speedup over final software is about 3.26x; realistic estimate about 1.78x. These are estimates only, not measured hardware results.

### Key Point
Hardware performance section is estimate-driven and explicitly separated from measured software data.

### Likely Question
What limits hardware gains most?

### Answer
Amdahl non-accelerated fraction plus data-transfer overhead and utilization limits.

## Slide 25 — Conclusion

### Show
Three bullets: software success, RTL success, next steps.

### Say
Software optimization is complete and successful at 75.76% measured improvement. Hardware RTL is implemented and simulation-verified. Remaining work is deployment integration, synthesis/timing/power characterization, and hardware-in-the-loop benchmarking.

### Key Point
Project achieved measured software goals and produced a credible, validated hardware foundation.

### Likely Question
What is the single biggest next risk?

### Answer
System integration overhead, especially transfer path efficiency, is the biggest risk to realizing estimated hardware speedups.

# Questions I Must Know

1. Q: What was the final measured software result?
A: Original 81.285 s, final 19.7062 s, improvement 75.76%.

2. Q: Was the 75.76% number estimated?
A: No. It is measured from official result artifacts.

3. Q: Why was Attempt 1 selected?
A: It introduced the main scalarization and produced almost the entire speedup, and it is the locked official final because the official result and submission pipeline were produced from it.

4. Q: Were Attempts 2 and 3 incorrect?
A: No. They were correctness-valid; in the later non-fast perf stat comparison Attempt 3 was actually slightly faster, but Attempt 1 remains the locked official final.

5. Q: What does flame graph width mean?
A: Width is sampled runtime contribution.

6. Q: What does flame graph height mean?
A: Height is call-stack depth.

7. Q: Which profiling tools were used?
A: pyperformance/pyperf, perf, and py-spy.

8. Q: Main measured bottleneck family?
A: CPython interpreter/runtime overhead, especially _PyEval_EvalFrameDefault and related frame/lookup costs.

9. Q: Why choose intersection/closest-hit for hardware?
A: It is frequent, arithmetic-dense, and has clean datapath/pipeline structure.

10. Q: What numeric format is in implemented RTL?
A: Signed fixed-point Q16.16.

11. Q: Why Q16.16 instead of FP32 in v1 RTL?
A: Practical synthesizable first implementation; FP32 full pipeline would significantly increase scope.

12. Q: Did you synthesize the RTL?
A: No synthesis results are claimed.

13. Q: Did you measure FPGA runtime speedup?
A: No. Only software timing and RTL simulation are measured.

14. Q: What simulator and outcomes?
A: ModelSim 10.5b; compile 0 errors/0 warnings; both testbenches pass.

15. Q: What is Amdahl's Law used for here?
A: To estimate upper-bound whole-program speedup from accelerating only a fraction P.

16. Q: Estimated hardware speedup range?
A: About 1.78x realistic and 3.26x optimistic over final software, both estimates.

17. Q: Biggest practical limiter for hardware gains?
A: Data transfer and integration overhead without batching/DMA.

18. Q: What remains in software after offload?
A: Scene setup, recursion control, shading composition, image write path, and orchestration.

19. Q: How did you prevent invalid claims?
A: By separating measured software, simulated RTL, estimated hardware, and proposed integration.

20. Q: What are the next concrete steps?
A: Implement real driver/interface, synthesize, deploy, and run hardware-in-the-loop benchmarks.

# 2-Minute Summary

I optimized the pyperformance Raytrace benchmark and then built a hardware acceleration prototype path. Starting from profiling evidence, I identified interpreter and runtime overhead as dominant, driven by repeated geometric work in hot loops. I implemented three software attempts. Attempt 1 introduced the main scalarization and produced almost the entire speedup; it is the locked official final because the official result and submission pipeline were generated from it. Attempt 3 was slightly faster in the later non-fast perf stat comparison, but it is not the locked official final.

The official before/after software comparison showed original 81.285 seconds and final 19.7062 seconds, which is a 75.76% improvement and exceeds the required threshold.

For hardware, I selected intersection plus closest-hit reduction as the best first kernel because it is repeated, arithmetic-heavy, and pipeline-friendly. I implemented real SystemVerilog RTL with modules for square root, sphere intersection, and top-level control, plus self-checking testbenches. Simulation in ModelSim passed with zero compile errors and all tests passing.

Hardware speedups are currently estimates only. Using Amdahl's Law and explicit assumptions, I reported a realistic estimate around 1.78x and optimistic around 3.26x over final software, while clearly stating that transfer overhead and system integration are key risks. So the project is complete on measured software optimization and simulation-validated hardware prototype, with deployment and synthesis as next steps.

# 30-Second Summary

This project achieved a measured software Raytrace speedup from 81.285 s to 19.7062 s, a 75.76% improvement, by selecting Attempt 1 based on correctness and benchmark evidence. Profiling showed interpreter-heavy bottlenecks, so for hardware I targeted intersection and closest-hit logic. I implemented SystemVerilog RTL and self-checking testbenches, and ModelSim simulation passed. Hardware performance numbers are estimates only, not measured deployment results, and the main next step is real HW/SW integration with efficient batched transfer.