# Hardware Acceleration Candidate Selection (No RTL Yet)

## Inputs Reviewed

- Project/subRay/docs/02_profiling_and_bottlenecks.md
- Project/subRay/docs/04_final_software_result.md
- Project/subRay/docs/05_before_after_profiling.md
- Measured hotspot evidence in profiling text reports:
  - Project/subRay/profiling/perf_report.txt
  - Project/subRay/profiling/perf_report_supplemental.txt

## Measured Hotspot Evidence Used

From perf text reports (baseline/supplemental), the dominant runtime is in Python execution machinery and repeated scalar numeric operations:

- _PyEval_EvalFrameDefault: about 20.63% self/children in perf_report.txt and about 23.60% in perf_report_supplemental.txt
- _PyEval_MakeFrameVector: about 3.63% in perf_report.txt
- frame_dealloc: about 2.41% in perf_report.txt and about 2.58% in perf_report_supplemental.txt
- binary_op1: about 2.35% in perf_report.txt and about 1.76% in perf_report_supplemental.txt
- PyFloat_FromDouble: about 1.68% in perf_report.txt and about 1.09% in perf_report_supplemental.txt
- PyTuple_GetItem: about 1.89% in perf_report.txt and about 1.85% in perf_report_supplemental.txt

Official measured software speedup already achieved:
- Original mean: 81.285 s
- Final mean: 19.7062 s
- Improvement: 75.76%

Interpretation for hardware planning:
- Profiles show Python interpreter overhead as the top measured cost.
- Hardware should therefore target stable, arithmetic-heavy inner kernels (where many Python numeric operations originate), not Python runtime internals themselves.

## Ranked Hardware Candidates

## Rank 1 (Selected): Sphere/Plane Intersection + Closest-Hit Reduction Kernel

Operation:
- Compute ray-object intersections for all spheres and plane, then select nearest valid hit.
- Includes the shadow-ray visibility test inner loop because it reuses the same intersection primitive.

Measured runtime importance:
- The measured top costs are interpreter and scalar numeric paths; intersection tests are the highest-frequency numeric kernel in ray tracing and a primary producer of those operations.
- Evidence is consistent with heavy repeated binary ops, float object conversions, tuple accesses, and frame activity.

Arithmetic operations:
- Per sphere test: dot products, subtracts, multiply-add patterns, discriminant evaluation, sqrt.
- Closest-hit: compare/select reduction across candidate t values.

Frequency of execution:
- Scene uses 7 spheres + 1 plane.
- For each ray hit evaluation in ray_colour: 7 sphere intersections + 1 plane intersection.
- For each light in visible_light (2 lights): another 7 sphere + 1 plane intersections.
- So per shaded hit point, minimum intersection checks are approximately:
  - sphere: 7 + (2 x 7) = 21
  - plane: 1 + (2 x 1) = 3
- Recursion depth up to 3 increases total checks further.

Inputs:
- Ray origin/direction, sphere parameters (center/radius), plane normal/offset, EPSILON threshold.

Outputs:
- Nearest hit distance and hit kind, plus visibility boolean for shadow ray checks.

Parallelism:
- Data-level parallelism across objects (sphere list) and across rays (pixel batch/tiles).
- Suitable for SIMD lanes, unrolled pipelines, or multi-core hardware workers.

Pipelining opportunity:
- Strong. Intersection math is mostly feed-forward arithmetic with compare/reduction.
- Natural multi-stage pipeline: load -> arithmetic -> discriminant/sqrt -> validity -> min-reduction.

Memory requirements:
- Small read-only scene parameter memory (few objects/lights in this benchmark).
- Streaming ray input and compact hit output buffers.

Communication overhead:
- Low if batched by tile/ray blocks.
- High if invoked per single ray due launch/transfer latency, so batching is required.

Hardware complexity:
- Moderate.
- Main cost drivers are sqrt/div handling, min-reduction control, and interface buffering.

## Rank 2: Vector Normalize + Reflect Arithmetic Unit

Operation:
- normalize() and reflect() vector math used in camera rays, normals, light directions, and reflection rays.

Measured runtime importance:
- Supported indirectly by measured binary_op1/PyFloat overhead.
- However measured data does not isolate normalize/reflect as clearly as intersection-heavy loops.

Arithmetic operations:
- Dot products, multiply-adds, reciprocal sqrt/sqrt, vector scaling.

Frequency of execution:
- Very frequent (per pixel ray generation and per shading/light computations), but call count is still coupled to intersection/control flow.

Inputs:
- 3D vectors and normals.

Outputs:
- Normalized vectors and reflected vectors.

Parallelism:
- High per-vector and across rays.

Pipelining opportunity:
- High for floating-point vector stages.

Memory requirements:
- Very small working set.

Communication overhead:
- Similar batching requirement; standalone normalization offload can become call-overhead bound.

Hardware complexity:
- Low to moderate.
- Easier than full intersection+reduction, but usually lower end-to-end impact when isolated.

## Rank 3: Checkerboard + Color Blend/Clamp (Shading Tail)

Operation:
- Checkerboard parity test, Lambert/specular scalar blending, and final RGB clamp/write path.

Measured runtime importance:
- Not evidenced as dominant in measured profiles.
- Likely secondary relative to intersection and general numeric dispatch overhead.

Arithmetic operations:
- Integer parity operations, scalar multiply/add, clamp to byte.

Frequency of execution:
- Per hit/pixel, but low arithmetic intensity per invocation.

Inputs:
- Hit point, material coefficients, base color, accumulated lighting.

Outputs:
- Final RGB values.

Parallelism:
- High across pixels.

Pipelining opportunity:
- Moderate.

Memory requirements:
- Small.

Communication overhead:
- Can dominate if offloaded alone due tiny compute payload.

Hardware complexity:
- Low.

## Final Accelerator Target

Selected target:
- Sphere/plane intersection + closest-hit reduction kernel (including shadow-ray visibility intersection checks).

Why this should be accelerated:
- It is the most compute-dense and repeatedly executed numeric kernel in the ray tracer.
- It aligns with measured evidence showing heavy scalar numeric/interpreter activity (binary_op1, float conversions, tuple access, frame churn) caused by repeated geometric computations.
- It has clear data parallelism and strong pipelining potential.
- It can be batch-invoked to keep communication overhead under control.

Why others were not selected first:
- Normalize/reflect alone: good arithmetic fit but narrower impact if intersection remains in software.
- Shading tail and color clamp: low arithmetic intensity, likely poor acceleration payoff relative to transfer/control overhead.
- Python runtime internals (for example _PyEval_EvalFrameDefault): dominant in profiles but not realistic RTL acceleration targets in this project context.

## Amdahl-Law Speedup Envelope (Assumption-Labeled)

Model:
- Speedup = 1 / ((1 - P) + P / S_accel)
- P = fraction of FINAL runtime spent in the selected intersection-related kernel
- S_accel = acceleration factor of that kernel

Assumptions (explicit):
- We do not have a direct measured P for FINAL from a workload-matched, kernel-attributed profile.
- Based on operation frequency and measured numeric/interpreter hotspot patterns, a plausible P range is 0.40 to 0.70.
- Consider a practical hardware kernel speedup S_accel = 10 and an upper bound S_accel -> infinity.

Estimated limits:
- If P = 0.40:
  - With 10x kernel speedup: total speedup about 1.56x
  - Theoretical max: 1 / (1 - 0.40) = 1.67x
- If P = 0.55:
  - With 10x kernel speedup: total speedup about 1.98x
  - Theoretical max: 1 / (1 - 0.55) = 2.22x
- If P = 0.70:
  - With 10x kernel speedup: total speedup about 2.70x
  - Theoretical max: 1 / (1 - 0.70) = 3.33x

How to interpret:
- These are theoretical bounds, not measured outcomes.
- They are useful for selecting the first RTL target and setting realistic expectations before implementation.

## Next Step Boundary

No RTL is implemented here.
This document only selects and justifies the first hardware acceleration target using available measured evidence and explicit assumptions.
