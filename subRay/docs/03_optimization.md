# Optimization Attempt 2

- Remaining measured hotspot: attempt1 profiling still shows interpreter dispatch and Python operation overhead as dominant (`_PyEval_EvalFrameDefault`, `binary_op1`, frame alloc/dealloc paths) in [subRay/profiling/perf_report_attempt1.txt](subRay/profiling/perf_report_attempt1.txt).
- Why Attempt 2 is justified: Attempt 1 delivered a major speedup but the remaining top costs are still Python execution overhead, so reducing global/bound lookup work in the hottest loops is a targeted next step.
- Exact planned change: in the Attempt 2 copy only, hoist hot global lookups and helper function references into local variables inside `ray_colour()` and `bench_raytrace()` to reduce repeated name-resolution overhead per pixel and per light.
- Expected benefit: lower interpreter overhead from fewer global lookups and call-site resolution operations in the deepest loops.
- Correctness risk: low to moderate; logic should remain identical, but incorrect rebinding could change control flow or coefficients if done incorrectly.

## Attempt 2 Implementation

- Location: `subRay/optimized/attempt2/`
- Single optimization implemented: local alias hoisting of hot global/helper lookups in `ray_colour()` and `bench_raytrace()`.
- No algorithmic changes and no edits to `subRay/original/`.

## Correctness First

- Command: `python3-dbg scripts/check_attempt2_correctness.py`
- Result file: `subRay/results/attempt2_correctness_report.txt`
- Outcome: `IDENTICAL=YES`
- Hashes:
	- original: `de4b11fd3678d70ba24c3654100970d64bf9d0b8026a18d6fc4d398cdc08057b`
	- attempt2: `de4b11fd3678d70ba24c3654100970d64bf9d0b8026a18d6fc4d398cdc08057b`

## Fast Benchmark Comparison

Sources:
- original preliminary baseline: `subRay/profiling/perf_baseline_stdout.txt`
- Attempt 1: `subRay/results/attempt1_fast.txt`
- Attempt 2: `subRay/results/attempt2_fast.txt`

Measured means:
- original preliminary baseline: `472 ms`
- Attempt 1: `103 ms`
- Attempt 2: `242 ms`

Improvement relative to original:
- Attempt 1: `((472 - 103) / 472) * 100 = 78.18%`
- Attempt 2: `((472 - 242) / 472) * 100 = 48.73%`

Concise result:
- Attempt 2 is faster than original baseline, but slower than Attempt 1 on the same fast methodology.
- Attempt 1 remains the best-performing variant so far.

# Optimization Attempt 3

- Remaining hotspot justification: profiling after Attempt 1 still shows Python call/frame overhead (`call_function`, `_PyEval_MakeFrameVector`, `frame_dealloc`) as a measurable cost in the shading path.
- Why another attempt is justified: the Lambert loop performs a per-light visibility function call (`visible_light`) at each hit point, so removing that hot call boundary is a targeted optimization aligned with observed overhead.
- Exact single change implemented: in `subRay/optimized/attempt3/run_benchmark.py`, the visibility test logic was inlined inside the Lambert lighting loop in `ray_colour()` to avoid per-light `visible_light()` function invocation and associated frame setup/teardown.
- Algorithm preserved: no changes to scene setup, recursion depth, reflection, intersection math, or baseline/original files.

## Attempt 3 Implementation

- Location: `subRay/optimized/attempt3/`
- Files created/updated for this attempt:
	- `subRay/optimized/attempt3/run_benchmark.py`
	- `subRay/optimized/attempt3/pyproject.toml`
	- `subRay/scripts/check_attempt3_correctness.py`

## Correctness Verification

- Command: `python3-dbg scripts/check_attempt3_correctness.py`
- Result file: `subRay/results/attempt3_correctness_report.txt`
- Outcome: `IDENTICAL=YES`
- Matching SHA256:
	- original: `de4b11fd3678d70ba24c3654100970d64bf9d0b8026a18d6fc4d398cdc08057b`
	- attempt3: `de4b11fd3678d70ba24c3654100970d64bf9d0b8026a18d6fc4d398cdc08057b`

## Short Preliminary Benchmark

- Command: `python3-dbg optimized/attempt3/run_benchmark.py --fast`
- Result file: `subRay/results/attempt3_fast.txt`
- Measured mean: `243 ms` (std dev `20 ms`)

## Comparison Against ORIGINAL

- ORIGINAL preliminary baseline: `472 ms`
- Attempt 3: `243 ms`
- Improvement vs ORIGINAL: `((472 - 243) / 472) * 100 = 48.52%`

Result kept as measured.
