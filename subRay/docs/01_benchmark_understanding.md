# Benchmark Understanding

**Project:** subRay HWSW Benchmark Optimization, Analysis, and Hardware Acceleration  
**Requested benchmark:** `raytrace` (resolved from the `<BENCHMARK>` placeholder using the VM's installed pyperformance registry)  
**Created:** 2026-09-13  
**Status:** Completed (Markdown only; DOCX no longer required per user decision 2026-09-13)  
**Code modification policy:** The benchmark implementation will be inspected read-only and copied unchanged. It will not be modified.

## Scope and Method

This document will identify the exact benchmark implementation executed by pyperformance and explain its workload without making performance claims. The investigation will:

1. Locate the pyperformance command or manifest entry for the benchmark associated with `subRay`.
2. Follow registration and imports to the implementation that directly defines the timed workload.
3. Record the entry point, call structure, algorithms, data, inputs, outputs, dependencies, and timing boundary.
4. Copy only the untouched relevant source files into `subRay/original/` while preserving useful relative paths.
5. calculate SHA256 checksums for those copied originals and save the raw checksum output.
6. Record potential bottlenecks only as unverified hypotheses because profiling has not begun.
7. Attempt to generate `subRay/docs/01_benchmark_understanding.docx` after this Markdown source is complete.

No benchmark execution, timing, profiling, optimization, or source modification is authorized in this step.

## Planned Evidence Commands

The following read-only operations are planned:

- Search repository manifests, scripts, and pyperformance references for likely ray-tracing benchmark names.
- Inspect the nearest registration entry and the source it invokes.
- Inspect pyperformance runner usage only far enough to define the timing boundary.
- Copy identified source files byte-for-byte into `subRay/original/`.
- Compute SHA256 hashes for both source and copied files and verify equality.
- Save raw inventory and checksum evidence under `subRay/logs/` or `subRay/results/`.
- Check for pandoc and generate the DOCX if available; otherwise document the failure.

## 1. Exact Benchmark Source File

The implementation executed by the VM's active pyperformance installation is:

```text
/usr/local/lib/python3.10/dist-packages/pyperformance/data-files/benchmarks/bm_raytrace/run_benchmark.py
```

Its local benchmark metadata is `bm_raytrace/pyproject.toml` in the same directory. The active launcher is `/usr/local/bin/pyperformance`, whose shebang selects `/usr/bin/python3` and whose Python entry imports `main` from `pyperformance.cli`.

## 2. pyperformance Benchmark Name

`raytrace`. The VM's benchmark list reports `raytrace`, the suite manifest contains `raytrace     <local>` at line 77, and `pyproject.toml` declares `[tool.pyperformance] name = "raytrace"`.

## 3. Entry Point

The script entry point is the `if __name__ == "__main__":` block. It creates `pyperf.Runner`, adds and parses benchmark arguments, records metadata, and calls:

```python
runner.bench_time_func('raytrace', bench_raytrace,
                       args.width, args.height,
                       args.filename)
```

The timed callback is `bench_raytrace(loops, width, height, filename)`.

## 4. Purpose of the Benchmark

The benchmark measures a small pure-Python ray tracer. Its metadata description is `Simple raytracer`. It exercises object-oriented Python, floating-point geometry, recursive ray evaluation, per-pixel shading, dynamic allocation, method dispatch, and byte-array output construction.

## 5. Workload Simulated

For every pyperf loop, the benchmark creates a `100 x 100` canvas by default, constructs a fixed scene, and renders it. The scene has two point lights, one large sphere, six smaller spheres, and an infinite halfspace used as a checkerboard floor. The camera starts at `(0, 1.8, 10)` and looks toward `(0, 3, 0)`. Rendering traces 10,000 primary rays at default dimensions, with additional shadow and recursive reflection rays depending on intersections.

## 6. Libraries Used

- Standard-library `array` for packed RGB bytes.
- Standard-library `math` for `sqrt`, `tan`, and `pi`.
- Third-party `pyperf` for timing, worker control, metadata, and results.

## 7. Python Modules Used

The benchmark directly imports `array`, `math`, and `pyperf`. The outer suite command is supplied by the separately installed `pyperformance` package.

## 8. Third-Party Dependencies

`pyproject.toml` declares one benchmark dependency: `pyperf`. The benchmark is packaged within `pyperformance 1.14.0`. It does not use NumPy, an image library, or an external ray-tracing engine.

## 9. Main Functions

- `firstIntersection(intersections)`: returns the nearest acceptable intersection.
- `addColours(a, scale, b)`: performs component-wise scaled RGB accumulation.
- `bench_raytrace(loops, width, height, filename)`: builds and renders the scene for each timed loop and returns elapsed time.
- `add_cmdline_args(cmd, args)`: propagates width, height, and optional filename to pyperf workers.

## 10. Main Classes

- `Vector`: vector arithmetic, normalization, dot/cross products, and reflection.
- `Point`: point arithmetic with vector/point type checks.
- `Sphere`: ray-sphere intersection and surface normals.
- `Halfspace`: ray-plane intersection and a constant normal.
- `Ray`: origin point, normalized direction, and point-at-time calculation.
- `Canvas`: packed RGB storage, pixel plotting, and optional PPM output.
- `Scene`: camera, objects, lights, rendering, recursive ray colouring, and shadows.
- `SimpleSurface`: reflected, Lambertian, and ambient shading.
- `CheckerboardSurface`: position-based procedural checkerboard colour.

## 11. Important Data Structures

- `Vector` and `Point` objects with `x`, `y`, and `z` attributes.
- `Ray` objects containing a point and normalized direction.
- `Scene.objects`, a list of `(geometry, surface)` tuples.
- `Scene.lightPoints`, a list of `Point` objects.
- Per-ray intersection lists containing `(object, time-or-None, surface)` tuples.
- RGB colours represented as three-element tuples.
- `Canvas.bytes`, an `array.array('B')` with `width * height * 3` elements.

## 12. Main Algorithms

1. Camera-ray generation derives viewport right/up vectors with cross products and generates one normalized primary ray per pixel.
2. Ray-scene intersection evaluates every object's `intersectionTime` and selects the nearest non-negative hit.
3. Sphere intersection computes a discriminant and the nearer hit parameter.
4. Halfspace intersection solves the ray-plane equation from a direction/normal dot product.
5. Surface shading combines recursive reflection, Lambertian diffuse light, and ambient colour.
6. Shadow testing casts a ray toward each light and checks scene objects for blockers.
7. Checkerboard shading selects between colours from coordinate parity.
8. Raster output clamps colour channels to `[0, 255]` and stores RGB bytes.

## 13. Main Loops

- `for i in range(loops)`: pyperf-controlled repetitions; each rebuilds and renders the scene.
- `for i in range(width * height)`: initializes canvas blue-channel bytes.
- Nested `for y` / `for x` loops in `Scene.render`: shade every pixel.
- `for y in range(6)`: add six small spheres each timed repetition.
- List comprehension over eight scene objects in `Scene.rayColour` for each ray.
- Loop over two lights in `visibleLights` for each shaded hit.
- Loop over scene objects in `_lightIsVisible` for shadow tests.
- Loop over visible lights in `SimpleSurface.colourAt` for diffuse accumulation.

## 14. Mathematical Operations

- 3D addition, subtraction, scalar multiplication, dot products, and cross products.
- Magnitude and normalization using `math.sqrt` and division.
- Field-of-view conversion from degrees to radians and `math.tan`.
- Sphere discriminant calculation and square root.
- Plane intersection division.
- Reflection using $r = v - 2(v \cdot n)n$.
- Lambertian shading from the light-direction/surface-normal dot product.
- Weighted RGB accumulation for reflected, diffuse, and ambient components.
- Absolute values, integer conversion, addition, and modulo for checkerboard parity.
- Pixel-coordinate flattening, colour conversion, and channel clamping.

## 15. Memory-Related Behavior

Each timed loop allocates a new canvas and scene. At default resolution, `Canvas.bytes` contains 30,000 byte elements and is initially built from a temporary Python list. Scene construction allocates lights, geometry, surfaces, tuples, and lists. Rendering creates many short-lived `Vector`, `Point`, and `Ray` instances. Each ray-colour call creates an intersections list, and visible-light evaluation creates a result list. Pixel writes mutate `array.array('B')` in place. Optional PPM conversion and file I/O occur after timing.

## 16. Function Call Structure

```text
pyperformance CLI
    -> run_benchmark.py __main__
        -> pyperf.Runner.bench_time_func(..., bench_raytrace, ...)
            -> bench_raytrace
                -> Canvas.__init__
                -> Scene construction and addLight/addObject
                -> Scene.render
                    -> Ray and Vector camera calculations
                    -> Scene.rayColour
                        -> Sphere.intersectionTime / Halfspace.intersectionTime
                        -> firstIntersection
                        -> geometry.normalAt
                        -> surface.colourAt
                            -> Scene.rayColour for reflection
                            -> Scene.visibleLights
                                -> Scene._lightIsVisible
                                    -> object.intersectionTime
                    -> Canvas.plot
```

## 17. Inputs

- `loops`: supplied internally by `pyperf`.
- `--width`: integer image width, default `100`.
- `--height`: integer image height, default `100`.
- `--filename`: optional PPM output path, absent by default.
- Scene geometry, lights, camera target, materials, field of view, and recursion limit are fixed in source.

## 18. Outputs

- `bench_raytrace` returns elapsed seconds to `pyperf`.
- `pyperf` records timing samples and metadata, including description, width, and height.
- Rendering produces an in-memory RGB canvas.
- If `--filename` is supplied, the final canvas is written as a binary P6 PPM after timing. The default invocation creates no image file.

## 19. How pyperformance Invokes It

The active `/usr/local/bin/pyperformance` launcher enters `pyperformance.cli.main`. The suite manifest registers `raytrace` as a local benchmark, while `pyproject.toml` maps the benchmark directory to that name. The suite launches `bm_raytrace/run_benchmark.py` with its configured Python interpreter and pyperf worker arguments. The script creates `pyperf.Runner`, parses standard pyperf options plus width/height/filename, and registers `bench_raytrace` through `Runner.bench_time_func`. `add_cmdline_args` propagates benchmark-specific arguments to worker processes.

## 20. What Exactly Is Timed

The timer starts inside `bench_raytrace` immediately before `for i in range(loops)` and stops immediately after it. Each timed loop includes canvas allocation/initialization; construction of the scene, lights, seven spheres, halfspace, and surfaces; complete pixel rendering; ray generation; intersections; nearest-hit selection; normals; shadow checks; recursive reflection; shading; and RGB writes to the in-memory canvas.

The timed region excludes module import, runner and argument setup, `range(loops)` construction, metadata assignment, and optional PPM serialization/file I/O. If a filename is requested, only the final canvas is written after `dt` is calculated.

## Execution Flow

```text
pyperformance CLI: raytrace
    |
    v
bm_raytrace/run_benchmark.py: __main__
    |
    v
pyperf.Runner.bench_time_func -> bench_raytrace
    |
    v
build Canvas + Scene -> Scene.render (100 x 100 default)
    |
    v
rayColour -> intersections -> shading/shadows/reflection -> Canvas.plot
    |
    v
elapsed seconds returned to pyperf
```

## Original Source Preservation and Checksums

Untouched copies are preserved at:

- `subRay/original/bm_raytrace/run_benchmark.py` (`12,042` bytes)
- `subRay/original/bm_raytrace/pyproject.toml` (`223` bytes)

| File | VM SHA256 | Preserved-copy SHA256 | Result |
|---|---|---|---|
| `run_benchmark.py` | `88ef4d9060d8e8f6ce40f376477aaf89cc808fa44813225a3071a05a1467f017` | `88ef4d9060d8e8f6ce40f376477aaf89cc808fa44813225a3071a05a1467f017` | Exact match |
| `pyproject.toml` | `b003d38fa3d472ac4a67a0e692160ba3e87c0b2dc60b94737767a79da45f159c` | `b003d38fa3d472ac4a67a0e692160ba3e87c0b2dc60b94737767a79da45f159c` | Exact match |

Direct noninteractive SSH copying was not used because that host command was skipped. The corresponding upstream `pyperformance` tag `1.14.0` files were accepted only after their hashes exactly matched the VM files. Initial editor-created copies normalized LF to CRLF and failed validation; they were replaced byte-for-byte from the verified downloads. The failed check and correction are preserved in `subRay/logs/01_vm_discovery.txt`.

## Potential Bottlenecks - Hypotheses Only

**UNPROFILED HYPOTHESES:** No profiling has been performed. Any items added here are guesses based only on source structure and must not be presented as measured bottlenecks or improvements.

The following are **hypotheses only**, not measured findings:

- The nested Python pixel loops may dominate because they execute 10,000 iterations at default dimensions per pyperf loop.
- Repeated all-object intersection scans may be expensive because primary/reflected rays test eight objects and shadow rays add more scans.
- Frequent allocation of `Vector`, `Point`, and `Ray` objects may create interpreter and allocator overhead.
- Python method dispatch and repeated attribute access in vector arithmetic and shading may be costly.
- `math.sqrt` calls in normalization and sphere intersections may contribute arithmetic cost.
- Recursive reflection may multiply ray, intersection, shading, and allocation work for hit pixels.
- Shadow visibility checks for each light may add substantial repeated intersection work.
- Per-pixel clamping, integer conversion, and three indexed byte-array writes may appear in profiles.
- Rebuilding the identical scene and initializing the canvas inside each timed loop may consume measurable time.

Profiling must test these guesses before any optimization is selected or accepted.

## Warnings, Errors, and Limitations

- The supplied benchmark field was the literal placeholder `<BENCHMARK>`. VM registry evidence resolved it unambiguously to `raytrace`; no name was inferred from source shape alone.
- DOCX generation is no longer required (user decision, 2026-09-13). Markdown is the sole deliverable format. An earlier pandoc attempt is retained for provenance in `subRay/logs/01_pandoc_check.txt`, but the missing DOCX is no longer a limitation.
- Long serial-console commands were repeatedly truncated. Partial commands were cancelled, and discovery continued with short commands.
- `pip show pyperformance` hung and was cancelled. The launcher, installed tree, and `pyperformance --version` instead established the active package and version.

## Activity Log

### 2026-09-13 - Understanding phase initialized

**Before action:** Create this Markdown source of truth before inspecting any benchmark files. Perform read-only discovery, preserve exact sources, calculate checksums, document all requested properties, attempt DOCX generation, and stop. Do not modify or execute benchmark code.

**Actual outcome:** The placeholder was resolved to the installed `raytrace` benchmark using the VM's benchmark list, manifest, local metadata, and source. No benchmark workload was executed and no benchmark source was modified.

### 2026-09-13 - DOCX generation attempted

**Before action:** Convert the completed Markdown source to `subRay/docs/01_benchmark_understanding.docx` with pandoc.

**Actual outcome:** The command failed with `CommandNotFoundException` because `pandoc` is not installed. No DOCX was produced. The exact error is preserved in `subRay/logs/01_pandoc_check.txt`.

### 2026-09-13 - QEMU reconnection planned

**Before action:** Start the Ubuntu Jammy QEMU VM from the existing project disk with four virtual CPUs, 4096 MiB RAM, a serial console, and host TCP port `2222` forwarded to guest SSH port `22`. Confirm the guest is available before issuing short read-only pyperformance discovery commands. Do not execute or modify benchmark code.

**Actual outcome:** QEMU started successfully from `Project/jammy-server-cloudimg-amd64-disk-kvm.fresh.img`. Ubuntu 22.04.5 reached the serial login prompt, networking initialized, and the OpenBSD SSH server started. The console is currently waiting for the root password. Passwords cannot be requested or transmitted through the assistant tools, so benchmark discovery is paused until the user enters the password directly in the QEMU terminal. No benchmark code was inspected, executed, or modified.
