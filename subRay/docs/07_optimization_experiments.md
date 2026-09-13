# Optimization Experiments

**Project:** subRay HWSW Benchmark Optimization, Analysis, and Hardware Acceleration
**Benchmark:** `raytrace`
**Created:** 2026-09-13
**Status:** In progress
**Constraint:** `subRay/original/` remains unchanged.

# Attempt 1

## Before Implementation

- **Targeted hotspot:** Python interpreter dispatch and object-heavy scalar geometry work visible in `_PyEval_EvalFrameDefault`, `_PyFrame_New_NoTrack`, `_PyEval_MakeFrameVector`, `binary_op1`, `PyFloat_FromDouble`, `_PyObject_GetMethod`, `PyTuple_GetItem`, and dictionary/type-lookup costs.
- **Exact planned modification:** Copy the original benchmark to `subRay/optimized/attempt1/` and rewrite the hottest vector/point/ray arithmetic path to use scalar local floats and tuple-based scene data instead of allocating many `Vector`, `Point`, and `Ray` objects in the inner render and shading loops.
- **Files to change:**
  - `subRay/optimized/attempt1/run_benchmark.py`
  - `subRay/optimized/attempt1/pyproject.toml`
  - helper validation/benchmark scripts under `subRay/scripts/` if needed for reproducible testing
- **Reason:** The measured profiler evidence shows the benchmark is dominated by Python execution overhead and temporary object churn rather than a single native numeric kernel.
- **Expected benefit:** Fewer Python method calls, fewer temporary objects, fewer frame or method-lookup events, fewer numeric boxing operations, and better locality on the hottest paths.
- **Correctness risks:** Rewriting vector algebra manually can introduce coordinate, normalization, reflection, shading, and intersection mistakes. The optimized copy must preserve the benchmark's existing behavior exactly, including quirks in the original implementation.

## Planned Correctness Check

1. Keep `subRay/original/` untouched.
2. Run the original and optimized attempt on the same fixed scene with a deterministic image output.
3. Compare the produced PPM files byte-for-byte and with SHA256.
4. Record both the command and the result under `subRay/results/attempt1/`.

## Planned Benchmark Method

1. Run the optimized attempt inside the same Ubuntu/QEMU VM used for the baseline.
2. Use the same high-level methodology as the baseline: `perf record -F 999 -g` with `python3-dbg` and pyperf-style repeated timing.
3. Save stdout, stderr, environment data, and timing results under `subRay/results/attempt1/`.
4. Summarize the measured comparison in `subRay/reports/attempt1_results.txt`.

## Activity Log

### 2026-09-13 - Attempt 1 prepared

**Before action:** Create this Markdown source-of-truth document before implementing the optimized copy. Record the exact targeted hotspot, planned modification, files to change, expected benefit, and correctness risks.

**Actual outcome:** Pending implementation, correctness validation, and benchmark results.
