# Optimization Plan

**Project:** subRay HWSW Benchmark Optimization, Analysis, and Hardware Acceleration
**Benchmark:** `raytrace`
**Created:** 2026-09-13
**Status:** Completed planning only
**Constraint:** No source code modifications in this step.

## Evidence Basis

This plan is based on measured profiling evidence from:

- `Project/subRay/profiling/perf_report.txt`
- `Project/subRay/profiling/flamegraph.svg`
- `Project/subRay/original/bm_raytrace/run_benchmark.py`

The main measured hotspot families visible in the saved profiling artifacts are:

- `_PyEval_EvalFrameDefault`: `20.63%` children, `20.61%` self
- `_PyFrame_New_NoTrack`: about `4.02%` children, `0.94%` self in the text report; `4.01%` in the flame graph
- `_PyEval_MakeFrameVector`: `3.63%` self
- `binary_op1`: `2.35%` self in the text report; `2.32%` visible in the flame graph
- `PyFloat_FromDouble`: `1.68%` self; visible children near `0.96%` and `0.73%`
- `_PyObject_GetMethod`: `1.70%` self; `1.04%` visible in the flame graph
- `_PyType_Lookup`: `1.29%` self; `1.16%` visible in the flame graph
- `PyTuple_GetItem`: `1.89%` self
- dictionary and object-lifecycle costs such as `dict_dealloc.lto_priv.0`, `lookdict_unicode_nodummy`, `PyDict_Contains`, `insertdict`, `frame_dealloc.lto_priv.0`, and `_PyDealloc`

These indicate that the original benchmark is dominated not by one native math kernel, but by repeated Python interpreter dispatch, temporary object creation, method lookup, frame creation, numeric boxing, dictionary access, and object teardown triggered by the raytracer's object-oriented scalar math style.

## Candidate 1 - Scalarize Hot Vector and Point Arithmetic

1. **Bottleneck being addressed.** Heavy Python arithmetic and interpreter overhead: `_PyEval_EvalFrameDefault`, `binary_op1`, `PyFloat_FromDouble`, `PyTuple_GetItem`, `_PyObject_GetMethod`, and frame-creation costs.
2. **Original implementation.** The code represents nearly all geometry using `Vector`, `Point`, and `Ray` objects, with many method calls such as `dot`, `cross`, `scale`, `normalized`, `reflectThrough`, `pointAtTime`, `intersectionTime`, and `colourAt`. The hottest source regions that trigger this style are [Project/subRay/original/bm_raytrace/run_benchmark.py](c:/Users/Sarim/homewroksbothsofthard/Project/subRay/original/bm_raytrace/run_benchmark.py#L245), [Project/subRay/original/bm_raytrace/run_benchmark.py](c:/Users/Sarim/homewroksbothsofthard/Project/subRay/original/bm_raytrace/run_benchmark.py#L266), [Project/subRay/original/bm_raytrace/run_benchmark.py](c:/Users/Sarim/homewroksbothsofthard/Project/subRay/original/bm_raytrace/run_benchmark.py#L315), and the vector helpers beginning at [Project/subRay/original/bm_raytrace/run_benchmark.py](c:/Users/Sarim/homewroksbothsofthard/Project/subRay/original/bm_raytrace/run_benchmark.py#L22).
3. **Proposed modification.** Replace the hottest inner-path geometry operations with plain scalar local variables (`x`, `y`, `z` floats) inside `render`, `rayColour`, and intersection/shading helpers. Keep external behavior the same while removing many temporary `Vector` and `Point` objects from inner loops.
4. **Why it could improve runtime.** Scalar locals avoid repeated Python method dispatch, reduce object creation and teardown, reduce tuple and attribute traffic, and cut the number of boxed float conversions on the hottest path.
5. **Whether it changes algorithm complexity.** No. The asymptotic complexity remains the same; only constant factors are targeted.
6. **Whether it reduces instructions.** Yes. It should reduce Python bytecode executed per ray and per shading step.
7. **Whether it reduces function calls.** Yes. Many geometry-method calls would be inlined into fewer local expressions.
8. **Whether it reduces allocations.** Yes. Temporary `Vector`, `Point`, and `Ray` allocations should drop significantly.
9. **Whether it improves memory access.** Yes. Fewer heap objects and fewer attribute lookups should improve locality.
10. **Correctness risks.** Moderate. Rewriting vector algebra manually risks sign errors, coordinate mix-ups, normalization mistakes, and altered reflection or shading behavior.
11. **Expected performance effect.** High. This candidate directly targets the largest measured families: interpreter frames, Python arithmetic dispatch, numeric boxing, method lookup, and object churn.
12. **How correctness will be verified.** Render identical scenes from original and optimized versions using a fixed width/height and compare the output PPM bytes or a hash of the generated image. Also preserve the original benchmark run as a behavioral reference.
13. **How performance will be measured.** Rerun the same baseline methodology with pyperformance and `perf`, compare mean and standard deviation against the original baseline, and regenerate the flame graph and perf report.

## Candidate 2 - Remove the Per-Ray Intersections List

1. **Bottleneck being addressed.** Frame creation, tuple access, allocation/deallocation, and interpreter overhead associated with building and scanning `intersections = [(o, o.intersectionTime(ray), s) for (o, s) in self.objects]` in `Scene.rayColour` at [Project/subRay/original/bm_raytrace/run_benchmark.py](c:/Users/Sarim/homewroksbothsofthard/Project/subRay/original/bm_raytrace/run_benchmark.py#L270).
2. **Original implementation.** For every ray, the code allocates a list of tuples for every object and then performs a second pass in `firstIntersection` at [Project/subRay/original/bm_raytrace/run_benchmark.py](c:/Users/Sarim/homewroksbothsofthard/Project/subRay/original/bm_raytrace/run_benchmark.py#L213).
3. **Proposed modification.** Replace the list comprehension plus second pass with one manual loop that tracks only the current best hit.
4. **Why it could improve runtime.** It removes one whole temporary container, reduces tuple creation, reduces `PyTuple_GetItem` pressure, and cuts deallocation costs.
5. **Whether it changes algorithm complexity.** No. It remains linear in the number of scene objects per ray.
6. **Whether it reduces instructions.** Yes. The loop body becomes simpler and eliminates a second traversal.
7. **Whether it reduces function calls.** Slightly. `firstIntersection` can be removed from the hot path.
8. **Whether it reduces allocations.** Yes. It removes the full intersections list and its tuples for every ray.
9. **Whether it improves memory access.** Yes. It avoids building and then rereading a temporary object graph.
10. **Correctness risks.** Low to moderate. The nearest-hit and EPSILON logic must remain identical.
11. **Expected performance effect.** Medium to high. The plan aligns with measured tuple access, deallocation, and frame overhead, though likely not as broadly as full scalarization.
12. **How correctness will be verified.** Compare chosen hit objects/times on a fixed scene or compare final rendered PPM output against the original.
13. **How performance will be measured.** Same pyperformance baseline comparison and repeated `perf` profiling.

## Candidate 3 - Hoist Repeated Attribute and Method Lookups in Hot Loops

1. **Bottleneck being addressed.** `_PyObject_GetMethod`, `_PyType_Lookup`, `lookdict_unicode_nodummy`, `_PyDict_GetItemHint`, `insertdict`, and related dictionary or type-cache activity.
2. **Original implementation.** The hot loops repeatedly resolve attributes like `canvas.width`, `canvas.height`, `self.objects`, `self.lightPoints`, method references such as `scene.rayColour`, and vector operations through normal Python attribute lookup in [Project/subRay/original/bm_raytrace/run_benchmark.py](c:/Users/Sarim/homewroksbothsofthard/Project/subRay/original/bm_raytrace/run_benchmark.py#L245), [Project/subRay/original/bm_raytrace/run_benchmark.py](c:/Users/Sarim/homewroksbothsofthard/Project/subRay/original/bm_raytrace/run_benchmark.py#L266), and [Project/subRay/original/bm_raytrace/run_benchmark.py](c:/Users/Sarim/homewroksbothsofthard/Project/subRay/original/bm_raytrace/run_benchmark.py#L315).
3. **Proposed modification.** Cache frequently used attributes and bound methods into local variables before the deepest loops.
4. **Why it could improve runtime.** Local variable access is cheaper than repeated dynamic attribute lookup and method resolution.
5. **Whether it changes algorithm complexity.** No.
6. **Whether it reduces instructions.** Yes, but by a smaller constant factor than scalarization.
7. **Whether it reduces function calls.** It reduces method-lookup machinery, though not necessarily the semantic call count.
8. **Whether it reduces allocations.** Minimal direct effect.
9. **Whether it improves memory access.** Slightly, by reducing dictionary and type-cache traffic.
10. **Correctness risks.** Low.
11. **Expected performance effect.** Medium. The profiling clearly shows lookup overhead, but it is probably a secondary win unless paired with larger structural changes.
12. **How correctness will be verified.** Compare output images and rerun the benchmark.
13. **How performance will be measured.** Same baseline-vs-optimized pyperformance and perf workflow.

## Candidate 4 - Reduce Object Dictionary Overhead With `__slots__` or Simpler Data Holders

1. **Bottleneck being addressed.** `dict_dealloc.lto_priv.0`, `lookdict_unicode_nodummy`, `PyDict_Contains`, `insertdict`, `_PyType_Lookup`, and object attribute-management costs.
2. **Original implementation.** `Vector`, `Point`, `Sphere`, `Halfspace`, `Ray`, `Canvas`, `Scene`, and the surface classes all use normal Python instance dictionaries.
3. **Proposed modification.** Add `__slots__` to fixed-shape classes or replace some hot data carriers with simpler tuple-like or scalar representations.
4. **Why it could improve runtime.** It can reduce attribute-dictionary allocation, lookup, and deallocation overhead for frequently created objects.
5. **Whether it changes algorithm complexity.** No.
6. **Whether it reduces instructions.** Somewhat.
7. **Whether it reduces function calls.** No major effect directly.
8. **Whether it reduces allocations.** Yes, especially dictionary-related allocations for objects.
9. **Whether it improves memory access.** Yes, potentially through denser object layout.
10. **Correctness risks.** Low to moderate. Some class behavior or introspection assumptions could change if any code expects instance dictionaries.
11. **Expected performance effect.** Medium. The measured dictionary and deallocation costs are real, but likely still secondary to full arithmetic/object scalarization.
12. **How correctness will be verified.** Rendered image equality and benchmark rerun.
13. **How performance will be measured.** Same baseline comparison and profiling workflow.

## Candidate 5 - Specialize the Pixel Write Path and Canvas Initialization

1. **Bottleneck being addressed.** Repeated per-pixel integer conversion, clamping, and indexed byte writes in `Canvas.plot` and the blue-channel initialization loop in `Canvas.__init__` at [Project/subRay/original/bm_raytrace/run_benchmark.py](c:/Users/Sarim/homewroksbothsofthard/Project/subRay/original/bm_raytrace/run_benchmark.py#L193) and [Project/subRay/original/bm_raytrace/run_benchmark.py](c:/Users/Sarim/homewroksbothsofthard/Project/subRay/original/bm_raytrace/run_benchmark.py#L200).
2. **Original implementation.** Every plotted pixel computes the flattened index, clamps each channel with nested `max(min())`, converts floats to ints, and performs three separate array writes. The constructor also loops over every pixel to initialize the third byte.
3. **Proposed modification.** Precompute more indexing state, streamline clamp or conversion logic, and reduce initialization work if semantics permit.
4. **Why it could improve runtime.** The per-pixel path runs 10,000 times per loop iteration and is on the rendering hot path.
5. **Whether it changes algorithm complexity.** No.
6. **Whether it reduces instructions.** Yes, modestly.
7. **Whether it reduces function calls.** Slightly, depending on how clamp logic is refactored.
8. **Whether it reduces allocations.** No major effect.
9. **Whether it improves memory access.** Slightly.
10. **Correctness risks.** Low. The main risk is changing channel rounding or output layout.
11. **Expected performance effect.** Low to medium. This is worth considering after larger interpreter/object-overhead wins.
12. **How correctness will be verified.** Exact PPM byte comparison with the original output.
13. **How performance will be measured.** Same pyperformance/perf methodology.

## Candidate 6 - Reorganize Shading and Visibility Loops to Reduce Repeated Work

1. **Bottleneck being addressed.** Repeated ray construction, repeated visibility checks over all objects, and repeated shading helper work in `Scene.rayColour`, `_lightIsVisible`, `visibleLights`, and `SimpleSurface.colourAt` at [Project/subRay/original/bm_raytrace/run_benchmark.py](c:/Users/Sarim/homewroksbothsofthard/Project/subRay/original/bm_raytrace/run_benchmark.py#L266), [Project/subRay/original/bm_raytrace/run_benchmark.py](c:/Users/Sarim/homewroksbothsofthard/Project/subRay/original/bm_raytrace/run_benchmark.py#L283), [Project/subRay/original/bm_raytrace/run_benchmark.py](c:/Users/Sarim/homewroksbothsofthard/Project/subRay/original/bm_raytrace/run_benchmark.py#L290), and [Project/subRay/original/bm_raytrace/run_benchmark.py](c:/Users/Sarim/homewroksbothsofthard/Project/subRay/original/bm_raytrace/run_benchmark.py#L315).
2. **Original implementation.** Each visible light check creates a new `Ray` and scans every object. Reflection recursively invokes `rayColour`, which repeats the same style of work.
3. **Proposed modification.** Reduce temporary objects and helper boundaries in the shading path, and combine visibility accumulation with other per-hit work where possible.
4. **Why it could improve runtime.** It attacks repeated function-call and object-allocation overhead in the secondary-ray path.
5. **Whether it changes algorithm complexity.** Not necessarily. If kept as a refactor only, the asymptotic structure is unchanged.
6. **Whether it reduces instructions.** Yes.
7. **Whether it reduces function calls.** Yes.
8. **Whether it reduces allocations.** Yes, especially if shadow-ray objects are reduced.
9. **Whether it improves memory access.** Slightly.
10. **Correctness risks.** Moderate. Visibility and reflection logic are easy to perturb.
11. **Expected performance effect.** Medium. This should help, but it is less directly supported by the visible measured symbols than Candidates 1-3.
12. **How correctness will be verified.** Exact image comparison and, if needed, targeted shadow/reflection regression scenes.
13. **How performance will be measured.** Same benchmark and profiling reruns.

## Ranked Candidate Ideas

1. **Scalarize hot vector and point arithmetic in `render`, `rayColour`, and the geometry helpers.** Best fit to the measured interpreter, arithmetic, frame, boxing, and object-churn hotspots.
2. **Remove the per-ray intersections list and fold nearest-hit selection into one loop.** Strong fit to tuple access and allocation/deallocation costs.
3. **Hoist repeated attribute and method lookups into locals in the deepest loops.** Low-risk and directly aligned with measured lookup overhead.
4. **Reduce object dictionary overhead with `__slots__` or simpler data holders.** Potentially useful, but more structural and less targeted than scalarization.
5. **Reorganize shading and visibility loops to reduce temporary rays and helper boundaries.** Useful, but correctness risk is higher and the measured evidence is less direct.
6. **Specialize the pixel write path and canvas initialization.** Valid but probably a smaller win than the interpreter/object overhead above.

## Optimization Attempt 1

**Selected attempt:** Scalarize hot vector and point arithmetic in the inner render and shading paths while preserving benchmark behavior.

Why this is Attempt 1:

- It directly targets the largest measured families: `_PyEval_EvalFrameDefault`, `_PyFrame_New_NoTrack`, `_PyEval_MakeFrameVector`, `binary_op1`, `PyFloat_FromDouble`, `_PyObject_GetMethod`, and dictionary-lookup overhead.
- The current implementation expresses almost every geometry operation as a new Python object plus multiple Python method calls.
- The benchmark is dominated by constant-factor interpreter costs, not by an obviously reducible algorithmic complexity term.
- A careful scalar rewrite can remove many temporary objects and method calls without changing the scene, shading model, or asymptotic structure.

Planned correctness check for Attempt 1:

1. Preserve the original benchmark unchanged.
2. Render the same scene from both versions with a fixed output file.
3. Compare the produced images byte-for-byte or with a deterministic hash.
4. If exact equality fails, inspect whether the failure is due to a real semantic bug or a benign formatting difference.

Planned performance check for Attempt 1:

1. Run the same pyperformance benchmark selection against the optimized variant.
2. Compare mean and standard deviation against the recorded original baseline.
3. Re-run `perf` and regenerate flame graph and report artifacts.
4. Accept the optimization only if correctness holds and the measured runtime improves.

## Output Format

Markdown is the sole deliverable format for this step. No DOCX is required.

## Activity Log

### 2026-09-13 - Optimization planning completed

**Before action:** Use measured bottlenecks only, create several ranked candidate ideas, and select Optimization Attempt 1 without modifying source code.

**Actual outcome:** Completed. Several candidate optimizations were ranked from strongest to weakest based on the measured profiling evidence. Optimization Attempt 1 is scalarization of the hot vector and point arithmetic path.
