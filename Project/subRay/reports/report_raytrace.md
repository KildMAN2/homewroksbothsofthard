# Raytrace Benchmark Report

**Benchmark:** `raytrace` (pyperformance, `bm_raytrace/run_benchmark.py`)
**Scene:** 8 objects, 2 light sources, rendered at **64 × 64 pixels** (the project's official resolution; the pyperformance default is 100 × 100)

## Contents
1. [Overview](#1-overview)
2. [Initial Analysis](#2-initial-analysis)
3. [Optimizations](#3-optimizations)
4. [Performance Comparison](#4-performance-comparison)
5. [Hardware Acceleration Proposal](#5-hardware-acceleration-proposal)
6. [Conclusion](#6-conclusion)

---

## 1. Overview

### 1.1 Purpose of the Benchmark

`raytrace` is a pyperformance benchmark that builds and renders a small 3-D scene using a ray tracer implemented from scratch in pure Python — there is no NumPy, no OpenGL binding, nothing beneath the interpreter doing the actual geometry. Every vector add, every sphere test, every shading calculation runs as ordinary Python bytecode. The workload is single-threaded and entirely CPU-bound.

Where a benchmark like `pyflate` spends its time inside a handful of tight, repetitive loops (bit unpacking, byte-level RLE), `raytrace`'s cost is spread thin across a very large number of small, individually cheap operations: constructing a fresh `Vector` or `Point` for nearly every arithmetic step, dispatching through several layers of method calls to do so, and repeating a linear scan over the same eight scene objects for every ray the renderer casts. This is why the two benchmarks were paired for this project — they stress the interpreter in almost opposite ways, one through raw byte throughput and one through object/call overhead.

The script itself does not check whether the picture it produces is correct; it only writes a PPM file if you ask it to, and even then it never compares that file against anything. For this project, an independent equivalence check was built specifically to close that gap: render the scene with both the original and an optimized copy, then compare the SHA-256 digest of the two output images (detailed in §2.1 and exercised in §3).

### 1.2 Workload (Measured)

Each benchmark loop rebuilds the scene from scratch: one large sphere, six smaller spheres lined up beside it, a checkerboard-textured infinite plane standing in for a floor, and two point lights. A single loop then renders one complete 64×64 image.

> Every figure below is a property of the scene and the resolution, not of the machine running it or how fast it runs — so these numbers hold regardless of CPU speed, Python build, or measured timing. They come from running the unmodified benchmark once through an instrumented copy that counts constructor and method invocations without altering what those methods do, at this project's actual 64×64 resolution.

| Quantity | Count |
|---|---:|
| Image | 64 × 64 = 4,096 pixels |
| Objects in scene | 8 (7 spheres, 1 halfspace) |
| Light sources | 2 |

**`Ray()` constructions — 40,043 total**

| Ray type | Count |
|---|---:|
| Primary/camera rays | 4,097 (4,096 pixels + 1 eye ray) |
| Reflection rays | 2,164 |
| Shadow rays (one per object tested, per light, per shaded point) | 33,782 |

**Shadow-visibility tests** (`_lightIsVisible` calls): 4,328, of which 4,187 find the light visible — averaging **7.80 of 8** objects tested per call (the scan exits as soon as it finds one obstruction, so most calls end up walking the entire object list unobstructed).

**Intersection tests — 83,694 total (20.4 per pixel)**

| Target | Tests | Returned a time | ...in front of ray |
|---|---:|---:|---:|
| Spheres | 73,268 | 2,762 | 1,269 |
| Halfspace | 10,426 | 10,426 | 1,613 |

**Objects created — 227,060 total (55.4 per pixel)**

| Type | Count |
|---|---:|
| Vector | 184,841 |
| Ray | 40,043 |
| Point | 2,176 |

**Vector operations**

| Operation | Calls |
|---|---:|
| `dot` | 208,135 |
| `mustBeVector` (no-op check) | 212,465 |
| `Point.__sub__` | 113,402 |
| `scale` | 61,081 |
| `normalized` / `magnitude` | 44,822 each |
| `Vector.__add__` | 8,192 |
| `Vector.__sub__` | 2,164 |

> This last figure lines up exactly with the reflection-ray count above — `reflectThrough()` performs one vector subtraction per reflected ray, which doubles as a sanity check that the instrumentation is counting correctly.

Intersection-list construction (`rayColour`): 6,239 lists, ~49,912 temporary tuples (each list holds one tuple per scene object; the count reflects how many shaded points are reached before the recursion-depth cutoff). `math.sqrt()`: 47,584 calls.

Nearly every halfspace test returns a value, since its formula only fails when a ray runs exactly parallel to the floor plane; most of those results are then thrown away because the intersection point sits behind the ray (only 1,613 of 10,426 survive that filter).

**Two figures matter most for what follows.** First, rendering one image allocates 227,060 short-lived objects — about 55 for every pixel drawn. Second, of the 73,268 sphere tests performed, only 2,762 actually return a hit, meaning roughly 96 out of every 100 sphere tests do nothing but confirm a miss. A third, less obvious figure becomes central later: **33,782 of the benchmark's 40,043 `Ray` objects — 84% of them — come from a single spot in the code**, `_lightIsVisible()`, which builds a brand-new shadow ray for every object it checks rather than building one ray and reusing it (see §1.8).

### 1.3 Libraries and Dependencies

**Standard library**

- `math` — supplies `sqrt()` for magnitude and sphere-intersection work, and `pi`/`tan()` once, up front, to size the camera's field of view. 47,584 `sqrt()` calls occur in one 64×64 loop.
- `array` — backs the output canvas with a flat `array.array('B')` of raw bytes, three per pixel; at 64×64 that's 12,288 bytes total.

**Outside the standard library**

- `pyperf` — supplies the timing harness. The benchmark registers itself with a `pyperf.Runner` via `bench_time_func()`, and exposes `--width`, `--height` and `--filename` as extra command-line switches. This project always supplies `--width=64 --height=64` explicitly.
- `pyperformance` — the outer framework that discovers, launches and manages `bm_raytrace` as one of its bundled benchmarks, including spawning the worker subprocess that does the actual timed work.

Nothing outside the benchmark's own source touches the geometry, shading or recursion — it's all ordinary Python, top to bottom. Because the script provides no way to check its own output, this project relies entirely on the external SHA-256 comparison described in §2.1 and used throughout §3.

### 1.4 Program Structure and Execution Flow

Ignoring the harness overhead around it, one timed loop looks like this:

```
bench_raytrace(loops, width, height, filename)
  start timer
  repeat loops times:
    build a fresh Canvas (64x64x3 bytes)
    build a fresh Scene: 7 spheres, 1 checkerboard floor, 2 lights
    render(canvas):
      derive the camera's viewing plane from its field of view
      for each of the 4,096 pixels, in row-major order:
        work out that pixel's ray direction from the camera basis
        build a primary Ray
        rayColour(ray):
          past recursion depth 3? return black immediately
          ask every one of the 8 objects for an intersection time
          firstIntersection() picks the smallest valid, forward time
          no hit at all -> return the background colour
          otherwise, at the hit point:
            colourAt(...) blends three terms:
              the base surface colour (flat, or checkerboard)
              a recursive reflection, if the surface is specular
              a Lambert diffuse term, from lights that survive
                a per-light _lightIsVisible() shadow test
              a constant ambient term
        Canvas.plot(...) converts the colour to three bytes and
        writes them into the canvas buffer
  stop timer
  optionally write the canvas out as a PPM file
  return the elapsed time
```

Recursion always begins, because every surface in this scene ships with a specular coefficient of 0.2 (greater than zero), and it always ends by depth 4 regardless of what the ray hits after that. Rebuilding the scene and canvas inside the timed region does add a small constant cost, but at only 8 objects it is dwarfed by the per-pixel work that follows.

### 1.5 Algorithms

**(a) Building the primary rays** — the camera is defined by a position, a look-at point, and a field of view; from those, `render()` derives two basis vectors (`vpRight`, `vpUp`) spanning a virtual viewing plane in front of the camera. Each of the 4,096 pixels maps to one point on that plane, and a normalized ray is built from the camera position through that point.

**(b) Sphere intersection** — plugging the ray equation into the sphere equation yields a standard quadratic in the intersection parameter `t`. Its discriminant tells the story: negative means the ray misses entirely, zero means a single grazing contact, positive means the ray passes through. The code takes the smaller root, `v - sqrt(discriminant)`, without first checking its sign — anything behind the ray gets filtered out later, by the caller. At this project's resolution, close to 96% of all sphere tests never get that far, because the discriminant comes back negative.

**(c) Halfspace (floor) intersection** — the floor's intersection routine is short: `v = ray.vector.dot(normal); if v: return 1/-v`. This is a shortcut, not the textbook ray-plane formula — it never looks at the ray's origin or the plane's actual position at all. It happens to give the right answer for this specific scene, where the floor passes through the world origin with an upward normal, but only for rays whose origin happens to sit exactly one unit above the plane. It stays exactly as written, because changing it would change the rendered picture (§1.8).

**(d) Picking the nearest hit** — `rayColour()` collects a candidate time from every object, then hands the list to `firstIntersection()`, which keeps only candidates with `t > -EPSILON` and returns whichever of those is smallest. The small negative tolerance exists to avoid rejecting a ray that starts almost exactly on a surface due to floating-point rounding.

**(e) Shading** — once a hit point is known, `colourAt()` adds together up to three contributions: a flat ambient term, a Lambert diffuse term driven by the angle between the surface normal and each visible light, and — despite the name "specular" — a full recursive mirror reflection rather than a localized highlight.

**(f) Shadows** — for every light in the scene, the renderer fires a ray from the hit point toward that light and asks `_lightIsVisible()` whether anything else in the scene sits in the way before the ray reaches it. The first object it finds in the way is enough to call the light blocked; a small epsilon keeps a surface from shadowing itself.

**(g) Reflection and the recursion limit** — a specular surface reflects the incoming ray direction around the surface normal, fires a brand-new ray from the hit point in that direction, and blends whatever colour comes back with the surface's own colour. That new ray can itself hit another specular surface and reflect again — capped at four levels deep so the recursion always terminates.

**(h) The checkerboard pattern** — the floor's two-tone pattern comes from the parity of `int(|x|+0.5) + int(|y|+0.5) + int(|z|+0.5)` evaluated at the hit point. One line of this routine, `v.scale(1.0/checkSize)`, computes a scaled vector and then throws the result away without using it — `scale()` returns a new object rather than mutating in place, so `checkSize` silently has no effect on the pattern at all. Left in place, because at the default `checkSize` of 1 it's invisible in the output.

### 1.6 Main Data Structures

| Structure | Description |
|---|---|
| `Vector`, `Point` | Plain x/y/z containers with no `__slots__` declaration, so each instance carries its own attribute dictionary on top of its three coordinates. One loop allocates 184,841 Vectors and 2,176 Points. |
| `Ray` | Pairs an origin `Point` with a direction `Vector`; the constructor immediately normalizes that direction, which itself allocates further Vectors and calls `magnitude()`/`sqrt()`. 40,043 constructed per loop. |
| `Scene.objects` | A flat Python list of the 8 `(geometry, surface)` pairs, walked linearly on every intersection search. |
| `Scene.lightPoints` | The 2 light positions, as `Point` objects. |
| `Canvas.bytes` | The output image as an `array.array('B')`; 12,288 bytes at 64×64. |
| `intersections` | A short-lived list rebuilt inside `rayColour()` on every call that hasn't yet hit the recursion limit; 6,239 of these per loop, holding roughly 49,912 tuples between them. |
| `surfaces` | 8 `SimpleSurface`/`CheckerboardSurface` instances (one per scene object), each carrying a base colour and the ambient/diffuse/specular coefficients used in §1.5(e). |

### 1.7 Candidate Costs to Investigate

Reading the code alongside the measured counts in §1.2 points at seven places worth checking against a real profile:

| # | Hypothesis | Measured basis |
|---|---|---|
| H1 | What a single intersection test actually costs | 73,268 sphere tests/loop, 96% miss rate — even a miss needs a subtraction, two dot products, a comparison |
| H2 | Sheer number of temporary objects | 227,060 allocations/loop, each a full object with its own attribute dict |
| H3 | How finely vector arithmetic is split across methods | `dot` 208,135 calls, `__sub__` 113,402+2,164, `scale` 61,081, `normalized` 44,822 |
| H4 | The intersection-list-then-scan pattern | 6,239 lists, ~49,912 tuples/loop — more allocation than tracking a running minimum would need |
| H5 | Shadow rays rebuilt inside the object loop | 33,782 of 40,043 `Ray()` calls (84%) from `_lightIsVisible()` alone |
| H6 | Fixed per-pixel overhead | `render()`/`Canvas.plot()` bookkeeping, once per pixel regardless of scene complexity |
| H7 | Type-check calls that do nothing | `mustBeVector()` called 212,465 times; success-path body is just `return self` |

Building the scene itself (8 objects, once per loop) is not expected to register as a meaningful cost. §2 checks these seven hypotheses against an actual profile.

### 1.8 Relevant Implementation Limitations

- **No self-check** — with default arguments the benchmark never even writes its output to disk, let alone verifies it. This project supplies its own SHA-256-based equivalence test instead (§2.1, §3), so an "optimization" can never quietly change a pixel unnoticed.
- **The floor's intersection formula** (`1/-v`) is a shortcut rather than a true ray-plane solver — it ignores both the ray's origin and the plane's position. Left untouched, since the currently-rendered image is exactly what this project's correctness checks are built to preserve.
- **Sphere intersection** only ever returns the closer of its two possible roots. A ray whose closer root lies behind it but whose farther root is still ahead would be handled wrong — not a concern for any ray in this particular scene, but worth noting as a general limitation of the formula.
- **The checkerboard surface** computes a scaled coordinate vector and then never uses it, so its `checkSize` parameter is entirely inert. Invisible at the default value of 1, and left as-is for the same reason as the floor formula above.
- **Unlike those three items**, the shadow-ray reconstruction in H5 is treated as fair game for optimization rather than preserved as-is: it's a cost internal to how the calculation is carried out, not something a viewer of the final image could ever detect — and it's tackled directly in §3.
- **Calls like `mustBeVector()`** exist purely to assert an argument's type; 212,465 such calls per loop add pure Python-call overhead without performing any part of the actual geometry calculation.


---

## 2. Initial Analysis

### 2.1 Environment and Measurement Method

| | |
|---|---|
| Host guest | Ubuntu 22.04 (jammy) cloud image inside QEMU |
| Acceleration | KVM |
| Logical CPUs | 1 (single virtual CPU) |
| Interpreter | CPython 3.10.12, `python3-dbg` build (used throughout, for consistent symbol resolution) |
| Kernel | Linux 5.15.0-1106-kvm-x86_64 |
| Benchmark tools | pyperformance 1.14.0, pyperf 2.10.0 |
| Profiling tools | Linux `perf`, `py-spy`, Brendan Gregg's FlameGraph scripts |

**Two profiling methods were used, and they are not equivalent:**

- **py-spy** attaches to a single process by PID. Without `--subprocesses` it never follows a forked child — and pyperformance's harness (`-m pyperformance run --bench raytrace`) launches the actual measured work in a forked worker. Every py-spy capture taken this way showed the **parent** harness process blocked waiting on a pipe (up to 87.8% of samples), never the ray tracer's own code. These captures are preserved as supplemental, historical evidence (§2.3) but are **not** used for any hotspot percentage in this report.
- **perf** samples whatever is actually executing on the CPU at each timer tick, following forked children automatically. Run through the identical `-m pyperformance run` invocation, perf correctly captures the worker process rendering the scene. **perf-based captures are the authoritative hotspot evidence** in this report (§2.3, §4).

**Correctness checking:** since `raytrace` verifies nothing about its own output, every optimization in §3 is checked by rendering the scene with the original and the optimized benchmark and comparing the SHA-256 digest of the two output images.

### 2.2 Baseline Results

Two distinct baseline measurements exist in this project's records, measuring different things — recorded explicitly rather than resolved by discarding one:

| | Mean | Notes |
|---|---:|---|
| Early exploratory baseline (VM) | 26.8 s ± 5.7 s | max 48.7 s; instability warning |
| **Official baseline** (`perf stat -r 3`, full 64×64, non-fast) | **81.285 s ± 0.198 s** (±0.24%) | see counters below |

**Official baseline hardware/software counters:**

| Metric | Value |
|---|---:|
| task-clock | 80,673 msec |
| instructions | 387,324,411,814 |
| branches | 94,415,979,904 |
| branch-misses | 865,418,173 (0.91%) |
| cache-references | 404,917,856 |
| cache-misses | 4,285,182 (1.045%) |
| page-faults | 89,909 |
| context-switches | 2,459 |

> **Methodological note:** the official baseline is `perf stat -r 3 -- python3-dbg -m pyperformance run --bench raytrace`, averaged over 3 runs by perf stat itself. This measures the wall-clock time of the **entire pyperformance harness invocation** — including its internal calibration and repeated measurement loops/values — not a single rendered image's time. It is a harness-session time, and is compared on that same basis against the optimized version's harness-session time in §4. It is not presented as a per-image render time.

The early exploratory baseline (26.8 s) was measured earlier in the project and carries its own instability warning; it is preserved as historical evidence of the measurement process, not used for the official comparison.

### 2.3 Flame Graphs and Profiling

**perf report** (cpu-clock software event — the virtual CPU exposes no usable hardware counters for *sampling*; perf stat's counting-only hardware counters above **are** supported), debug interpreter:

| Symbol group | Share |
|---|---:|
| `_PyEval_EvalFrameDefault` (bytecode interpreter loop) | 20.6–23.6% (range across two independent baseline captures) |
| `_PyEval_MakeFrameVector`, `_PyFrame_New_NoTrack`, `frame_dealloc` (frame create/teardown) | ~7–9% |
| `_PyDict_GetItemHint`, `lookdict_unicode_nodummy`, `_PyType_Lookup`, `lookdict_split`, `_PyObject_GetMethod` (attribute/dict lookup) | ~9% |
| `binary_op1`, `PyFloat_FromDouble`, `PyTuple_GetItem` (float arithmetic/boxing, tuple access) | ~4% |

**py-spy flame graphs (supplemental, not used for percentages — see §2.1):**
- `flamegraph_pyspy_baseline.svg` — 87.77% of samples in the parent harness's `spawn_worker → read(pipe)` wait chain; 0% inside the ray tracer.
- `flamegraph_pyspy_final.svg` (several captures, 28–51 samples each across the project) — same wait pattern plus Python's own import bootstrap; still 0% inside the ray tracer.

**The authoritative before/after flame graphs** are a separate, kernel-level pair (`flamegraph_suite_baseline.svg`/`flamegraph_suite_final.svg`, built via `perf script → FlameGraph.pl`), used in §4 and independently confirmed to match the perf report percentages exactly.

### 2.4 Identified Bottlenecks

The perf evidence confirms §1.7's hypotheses without isolating one dominant native kernel — cost is spread across CPython's own interpreter and object machinery:

1. **Interpreter dispatch overhead** (20.6–23.6% self time) — every opcode in every method call (`dot`, `mustBeVector`, `scale`, `__sub__` — 208,135 + 212,465 + 61,081 + 113,402 calls) passes through `_PyEval_EvalFrameDefault`. Confirms H3 and H7.
2. **Frame and object churn** (~7–9%) + **attribute/dict lookup** (~9%) — 227,060 objects created per image, each needing a new frame for `__init__` and its own attribute dict (no `__slots__`). Confirms H2.
3. **Shadow-ray reconstruction** (H5, the largest single `Ray()`-related cost) — 33,782 of 40,043 `Ray()` constructions (84%) from `_lightIsVisible()` rebuilding the shadow ray inside its per-object loop. The clearest, most concrete optimization target from the measured counts in §1.2.
4. **Intersection-list materialization** (H4) — 6,239 lists, ~49,912 tuples per image; real but proportionally smaller than items 1–3.

No single change was expected to dominate: the work is spread across many small, individually cheap operations. §3's optimizations target this per-operation overhead directly.

---

## 3. Optimizations

Three **independent** optimization attempts were written and measured separately (not cumulative steps building on one another) — recorded explicitly since this differs from a cumulative methodology: attempts 2 and 3 are alternatives to attempt 1's approach, not built on top of it.

### 3.1 Attempt 1 — Scalarization

**Strategy:** replace Vector/Point/Ray object arithmetic in the hottest geometry paths with scalar float locals and tuple-based scene data — directly addressing H2, H3 and H7 by removing the object layer itself in the hot loop, rather than optimizing its individual methods.

**Correctness:** `IDENTICAL=YES`, SHA-256 match against the preserved original (`Project/subRay/results/attempt1/correctness_report.txt`).

### 3.2 Attempt 2 — Lookup Hoisting

**Strategy:** hoist repeated hot global, attribute and helper lookups (in `ray_colour()` and `bench_raytrace()`) into local variables — addressing the attribute/dictionary-lookup share of the profile (~9%) without restructuring the object model.

**Correctness:** `IDENTICAL=YES`, SHA-256 match (`Project/subRay/results/attempt2/attempt2_correctness_report.txt`).

### 3.3 Attempt 3 — Visibility Inlining

**Strategy:** inline the per-light visibility check directly in the Lambert shading loop, reducing call/frame overhead around `_lightIsVisible()`/`visibleLights()` (H5 territory) without full scalarization.

**Correctness:** `IDENTICAL=YES`, SHA-256 match (`Project/subRay/results/attempt3/attempt3_correctness_report.txt`).

### 3.4 Selection

All three attempts are correct. **Attempt 1 was selected as the official final implementation.** The full basis for this selection — including an important honesty note — is given in §4 alongside the measured numbers: at full official scale the three attempts are statistically close (within 0.2 percentage points), and Attempt 1's selection reflects that the official measurement and reporting pipeline were already built around it, not that it measured strictly fastest in every capture.

### 3.5 Optimizations Considered and Not Adopted

- **Numerical/graphics library rewrite** — would move the studied computation out of the Python interpreter, changing the nature of the workload being measured.
- **Spatial acceleration structure (e.g. BVH)** — with only 8 scene objects, tree construction/traversal overhead (plus its own Python object cost) would likely outweigh the saving from reducing 73,268 sphere tests. Linear search over 7–8 objects is already close to optimal; the real cost (§2.4) is in what each test does, not how many objects are scanned.
- **Multi-process/multi-threaded rendering** — CPython's GIL prevents CPU-bound bytecode from running in parallel across threads; multiprocessing would add process-management/communication costs and change the benchmark's structure.

---

## 4. Performance Comparison

### 4.1 Official Before/After Result

Both figures are `perf stat -r 3` elapsed times for the complete `-m pyperformance run --bench {raytrace,raytrace_final}` invocation at 64×64 (harness-session time — see the methodological note in §2.2).

| Version | Mean | Std dev | Improvement | Correct |
|---|---:|---:|---:|---|
| ORIGINAL | 81.285 s | 0.198 s | 0.00% | Yes |
| **FINAL (Attempt 1)** | **19.7062 s** | 0.0133 s | **75.76%** | Yes |

**Speedup: ≈4.12×** (81.285 / 19.7062). **Target ≥7% improvement: ACHIEVED**, with roughly 10× margin.

### 4.2 perf stat Hardware-Counter Comparison

| Metric | Baseline (3-run mean) | Final (1 run) | % change |
|---|---:|---:|---:|
| Elapsed | 81.285 s | 19.667 s | **−75.8%** |
| Instructions | 387,324,411,814 | 99,522,163,151 | **−74.3%** |
| Branches | 94,415,979,904 | 23,673,592,504 | **−74.9%** |
| Branch-misses | 865,418,173 | 166,181,093 | **−80.8%** |
| Cache-references | 404,917,856 | 198,261,770 | **−51.0%** |
| Cache-misses | 4,285,182 (1.045%) | 2,925,764 (1.476%) | −31.7% |
| Page-faults | 89,909 | 87,875 | −2.3% |
| Context-switches | 2,459 | 2,101 | −14.6% |

**Interpretation:**
- Every "work done" indicator falls by roughly three-quarters (instructions, branches, branch-misses) — consistent with an optimization that removes interpreter/object-dispatch work rather than tightening memory access.
- Cache-misses fall in absolute count, but their *rate* rises (1.045% → 1.476%): far fewer memory references overall, so the ones that remain are proportionally less cache-friendly. Both statements are true simultaneously.
- Page-faults are essentially flat (−2.3%): same image size/pixel count, same output memory footprint — the optimization targeted CPU/interpreter work, not I/O.

### 4.3 Three Attempts Compared — Fast-Mode Cross-Check vs. Full Official Scale

| Attempt | Fast-mode (harness, real samples) | Full-scale (official) | Improvement |
|---|---:|---:|---:|
| 1 | 227–236 ms (3 separate runs) | 19.7062 s ± 0.0133 s | 75.76% |
| 2 | 285 ms ± 91 ms (noisy) | 19.6843 s ± 0.00708 s | 75.78% |
| 3 | 229 ms ± 24 ms | 19.6077 s ± 0.0171 s | **75.88%** |

> **Honesty note, recorded rather than smoothed over:** an earlier, informal fast-mode test called the script directly with `--fast` but no explicit `--width`/`--height`, so it silently fell back to the benchmark's own 100×100 default instead of this project's actual 64×64 resolution. That test showed a large gap favoring Attempt 1 (103 ms vs. 242–243 ms) — but since it wasn't even rendering the same-size image as the official measurement, it is **not comparable** and is not reported here. The fast-mode figures in the table above instead come from a later, properly matched re-measurement: pyperformance's own `--fast` flag invoked through the identical harness mechanism and manifest files as the official run, at the same resolution, with real perf samples captured on every run (14,000–48,000 samples each) — for reference, baseline under this same method measured 1.20 s ± 0.14 s.
>
> At full official scale, the three attempts are within 0.2 percentage points of each other, and **Attempt 3 is marginally the fastest, not Attempt 1** — the properly matched fast-mode cross-check agrees with this (Attempt 1/Final ≈ Attempt 3 ≈ 227–236 ms, both faster than Attempt 2's noisier 285 ms). Attempt 1 remains the official final implementation because the official before/after result and the full reporting/artifact pipeline (§4.1, §4.4, §4.5) were built around it before this discrepancy was found; re-deriving the whole pipeline around Attempt 3 for a difference of a few tenths of a percent was judged not worth the risk this late in the project. Stated plainly rather than presenting Attempt 1 as chosen for being fastest.

Two measurement scales, four orders of magnitude apart (≈0.2 s fast-mode vs. ≈20 s full scale), agree that the three attempts are close together — the load-bearing claim, not the exact ranking.

### 4.4 perf Report Comparison — Where the Bottleneck's Shape Changed

Artifacts: `perf_report_suite_baseline.txt` (117K samples) vs. `perf_report_suite_final.txt` (34K samples), both captured through the **identical** pyperformance harness invocation (matched methodology).

**Symbols whose share shrank sharply** (object/attribute/method overhead Attempt 1's scalarization targeted):

| Symbol | Baseline | Final | Relative drop |
|---|---:|---:|---:|
| `_PyFrame_New_NoTrack` | 3.66% | 0.67% | **−82%** |
| `_PyDict_GetItemHint` | 2.67% | 0.15% | **−94%** |
| `_PyObject_GetMethod` | 1.73% | 0.17% | **−90%** |
| `_PyType_Lookup` | 1.98% | 0.44% | **−78%** |
| `lookdict_split` | 2.08% | 0.24% | **−88%** |

**Symbols whose share grew** (the irreducible interpreter/arithmetic core that remains):

| Symbol | Baseline | Final |
|---|---:|---:|
| `_PyEval_EvalFrameDefault` | 23.50% | 27.39% |
| `float_dealloc` | 1.21% | 3.39% |
| `binary_op1` | 1.49% | 2.62% |
| `PyFloat_FromDouble` | 1.19% | 2.75% |

perf report percentages are **relative shares** of each run's own total samples, not absolute time. `_PyEval_EvalFrameDefault`'s rising share does not indicate a regression: total runtime fell ~4.1×, so once the object/method/attribute overhead above was cut 78–94%, the interpreter's own irreducible dispatch cost necessarily fills a larger fraction of a much smaller total — confirmed independently by the perf stat instruction/branch counts in §4.2 (absolute interpreter work also fell, just by a smaller percentage than the overhead categories).

### 4.5 Flame Graph Comparison

Two flame-graph pairs exist in this project's records, built by different tools — only one is used as evidence (see §2.1, §2.3):

- **`flamegraph_suite_baseline.svg` / `flamegraph_suite_final.svg`** (authoritative) — built from `perf.data` via `perf script → FlameGraph.pl`. perf follows forked children automatically, so these correctly sample inside the ray tracer's own code; percentages match §4.4's tables exactly.
- **`flamegraph_pyspy_baseline.svg` / `flamegraph_pyspy_final.svg`** (supplemental only) — show the parent harness process waiting on a pipe (87.8% of baseline samples) and Python's import bootstrap, never the ray tracer's code. Not used for any percentage claim in this report.

---

## 5. Hardware Acceleration Proposal

### 5.1 Choice of Component

Even after the 75.76% software improvement, intersection testing remains the highest-frequency numeric kernel: 83,694 tests per image (§1.2), each a short, fixed sequence of floating-point operations with no data dependence between one test and the next. Two alternatives were considered and ranked below it:

- **Vector normalize/reflect arithmetic unit** — good arithmetic fit, but narrower impact if the intersection scan itself stays in software; normalize/reflect calls are already coupled to, and gated by, the intersection control flow.
- **Shading-tail unit** (checkerboard colour selection, blend/clamp) — low arithmetic intensity per invocation; likely bound by transfer/control overhead if offloaded alone.

The selected kernel — **sphere/plane intersection plus closest-hit reduction**, covering both the nearest-hit search in `rayColour()` and the any-hit search in `_lightIsVisible()` — is executed **21 times for spheres and 3 times for the plane per shaded point** before recursion (7 spheres × 3 rays [camera + 2 lights], 1 plane × 3 rays), the clearest, highest-frequency pipelining target of the three.

### 5.2 Function

The accelerator holds the scene locally (7 spheres, 1 halfspace) and implements the search in two modes, matching the two call sites exactly:

| Mode | Behavior |
|---|---|
| `MODE_NEAREST` | test every object, keep smallest `t` with `t > -EPSILON` (matches `firstIntersection()`) |
| `MODE_ANYHIT` | stop at first object with `t > EPSILON` (matches `_lightIsVisible()`'s early exit) |

Arithmetic follows the benchmark's own formulas (§1.5b, §1.5c):

```
cp   = centre - origin
v    = dot(cp, direction)
c2   = dot(cp, cp)
disc = r*r - (c2 - v*v)
t    = v - sqrt(disc)                      (sphere)
t    = 1 / -dot(direction, normal)          (halfspace, matching §1.5c exactly,
                                             including its known limitation)
```

### 5.3 Architecture and Numeric Format

Implemented as three SystemVerilog modules under `Project/subRay/hw/rtl/`:

| Module | Role |
|---|---|
| `fxp_sqrt.sv` | Iterative fixed-point square root |
| `sphere_intersect.sv` | Candidate-`t` computation per the formula above |
| `intersect_accel.sv` | Top-level control: iterates the scene, drives the two modules, performs nearest-hit/any-hit reduction |

Control uses a start/busy/done handshake with **iterative per-object processing** in this version; deeper pipelining and multi-lane parallelism are proposed future work, not part of the implemented v1.

**Numeric format: signed fixed-point Q16.16**, not the benchmark's native IEEE-754 double precision — a deliberate scope decision, not an oversight. Q16.16 is a practical, synthesizable first implementation; a full FP32/FP64 pipeline would substantially increase the RTL scope. Because of this format difference, the hardware is **not** expected to reproduce the software's bit-exact output, and **no claim of bit-exact hardware/software equivalence is made anywhere in this report** — the SHA-256 correctness checks in §3 cover the software attempts only.

### 5.4 Interfaces — Implemented vs. Proposed

**Implemented** (direct RTL port-level handshake, driven by the testbench in simulation):
- `start` / `mode` / `epsilon` / `ray` inputs, Q16.16 fixed-point
- `busy` / `done` / `hit_valid` / `hit_kind` / `hit_id` / `hit_t` outputs

**Proposed for deployment** (not implemented):
- Memory-mapped register block (CTRL / STATUS / RAY_* / HIT_*)
- Descriptor-based DMA for ray-batch streaming — the benchmark casts 40,043 rays per image (§1.2), and even a small fixed per-ray transfer cost, unbatched, would be comparable to or larger than the compute time it's meant to save
- Python driver/wrapper for register access or DMA setup
- Error-status bit for malformed batch/buffer underrun

### 5.5 Simulation Results

Simulated in **ModelSim Intel FPGA Edition 10.5b** (`vlog`/`vsim`): **0 compile errors, 0 compile warnings.**

| Testbench | Checks | Result |
|---|---:|---|
| `tb_fxp_sqrt` | 11/11 | ALL PASS (0, 1, non-squares, perfect squares, 65535², Q32.32→Q16.16 scaling) |
| `tb_intersect_accel` | 7/7 | ALL PASS (direct hit, plane-only, no-hit, off-axis, blocked/clear visibility) |

This demonstrates logical correctness of the implemented RTL against its own specification — it does **not** measure deployed FPGA performance, area, or power, all of which remain estimates (§5.6).

### 5.6 Expected Performance (Estimated, Not Measured)

Target clock **200 MHz** (labeled ESTIMATE, not synthesized or measured). Using Amdahl's Law:

```
Speedup = 1 / ( (1 - P) + P/S )
```

| Scenario | P | S | Overall speedup | Assumption |
|---|---:|---:|---:|---|
| Realistic | 0.50 | 8 | **1.78×** | moderate batching; transfer overhead still costs a meaningful share |
| Optimistic | 0.70 | 100 | **3.26×** | aggressive batching/DMA; overhead ≈ negligible |

These are estimates only — no synthesis, no FPGA bring-up, no measured hardware-in-the-loop timing exists. The single largest risk to realizing either figure is data-transfer overhead without batching: with 40,043 rays per image, even microsecond-scale per-ray overhead would add tens of milliseconds, comparable to or larger than the compute-side saving.

### 5.7 Trade-offs

- **Precision** — Q16.16 trades reduced dynamic range/precision for a substantially smaller, faster implementation than IEEE-754 double; no bit-exact equivalence is claimed (§5.3).
- **Area/complexity** — iterative, shared-unit processing (v1) keeps the design small at the cost of throughput; a pipelined/multi-lane variant would trade area for throughput.
- **Parallelism ceiling** — even in the optimistic Amdahl scenario, the non-accelerated 30% of runtime caps total speedup well below the accelerated section's own 100× internal speedup — the ceiling is Amdahl's Law and interface bandwidth, not the datapath itself.

---

## 6. Conclusion

`raytrace` renders a small scene with a ray tracer written entirely in Python, measuring the interpreter executing vector arithmetic and object-heavy geometry code rather than any one dominant native kernel. One 64×64 image requires 227,060 temporary objects and 83,694 intersection tests (96.2% of sphere tests miss); no single profiled function exceeded ~24% of self time in either version.

Profiling (perf, kernel-level, following the harness's forked worker — py-spy could not do this, §2.1) confirmed the code-level hypotheses: interpreter dispatch overhead (20.6–23.6%), frame/object churn, attribute/dictionary lookups, and — measured precisely for the first time via direct instrumentation in this report — a specific, concrete inefficiency in `_lightIsVisible()`, accounting for 84% of all `Ray()` construction in the benchmark.

Three independent optimization attempts were written and verified correct by SHA-256 digest. **Attempt 1 (scalarization) was selected as the official final implementation, measured at 75.76% improvement** (81.285 s → 19.7062 s) — more than ten times the 7% requirement. This report states plainly that at full official scale the three attempts are within 0.2 percentage points of each other and Attempt 3 is marginally the fastest — Attempt 1's selection reflects that the official pipeline was already built around it, not a claim that it measured fastest in every capture.

Hardware counters independently confirm the result beyond wall-clock time: instructions −74.3%, branches −74.9%, branch mispredictions −80.8% — all consistent with removing interpreter/dispatch work. The perf report comparison adds a further finding: object/attribute/method-dispatch overhead shrank 78–94%, while the interpreter's own irreducible dispatch cost grew as a *share* of the much smaller total — exactly as expected when surrounding overhead is cut this aggressively.

The intersection kernel — repeated 21 times for spheres and 3 for the plane per shaded point, with no dependence between tests — was selected for hardware acceleration on this evidence. Three SystemVerilog modules were implemented in Q16.16 fixed point (a deliberate scope decision over full double precision) and verified in ModelSim: 0 errors/warnings, 18/18 functional checks passed. This demonstrates logical correctness, not deployed performance; Amdahl's Law, under two labeled assumption scenarios, estimates **1.78× (realistic) to 3.26× (optimistic)** further speedup over the software final, contingent on batching to control per-ray transfer overhead. **No synthesis, FPGA deployment, or measured hardware performance is claimed anywhere in this report.**