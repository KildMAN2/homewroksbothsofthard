# Optimization Attempt 2

- Remaining measured hotspot: attempt1 profiling still shows interpreter dispatch and Python operation overhead as dominant (`_PyEval_EvalFrameDefault`, `binary_op1`, frame alloc/dealloc paths) in [Project/subRay/profiling/perf_report_attempt1.txt](Project/subRay/profiling/perf_report_attempt1.txt).
- Why Attempt 2 is justified: Attempt 1 delivered a major speedup but the remaining top costs are still Python execution overhead, so reducing global/bound lookup work in the hottest loops is a targeted next step.
- Exact planned change: in the Attempt 2 copy only, hoist hot global lookups and helper function references into local variables inside `ray_colour()` and `bench_raytrace()` to reduce repeated name-resolution overhead per pixel and per light.
- Expected benefit: lower interpreter overhead from fewer global lookups and call-site resolution operations in the deepest loops.
- Correctness risk: low to moderate; logic should remain identical, but incorrect rebinding could change control flow or coefficients if done incorrectly.

## Attempt 2 Implementation

- Location: `Project/subRay/optimized/attempt2/`
- Single optimization implemented: local alias hoisting of hot global/helper lookups in `ray_colour()` and `bench_raytrace()`.
- No algorithmic changes and no edits to `Project/subRay/original/`.

## Correctness First

- Command: `python3-dbg scripts/check_attempt2_correctness.py`
- Result file: `Project/subRay/results/attempt2_correctness_report.txt`
- Outcome: `IDENTICAL=YES`
- Hashes:
	- original: `de4b11fd3678d70ba24c3654100970d64bf9d0b8026a18d6fc4d398cdc08057b`
	- attempt2: `de4b11fd3678d70ba24c3654100970d64bf9d0b8026a18d6fc4d398cdc08057b`

## Profiling-Based Comparison (perf stat)

Sources:
- Baseline: `Project/subRay/profiling/perf_stat_baseline.txt`
- Attempt 1: `Project/subRay/profiling/perf_stat_attempt1.txt`
- Attempt 2: `Project/subRay/profiling/perf_stat_attempt2.txt`
- Attempt 3: `Project/subRay/profiling/perf_stat_attempt3.txt`

Measured elapsed means (non-fast):
- Baseline: `81.285 s`
- Attempt 1: `19.7062 s`
- Attempt 2: `19.68433 s`
- Attempt 3: `19.6077 s`

Improvement relative to baseline:
- Attempt 1: `75.76%`
- Attempt 2: `75.78%`
- Attempt 3: `75.88%`

Selection:
- All three attempts land within ~0.5% of each other (about 0.1 s on a ~19.7 s run), i.e. inside run-to-run measurement noise on this host.
- Attempt 1 is the foundational scalarization optimization; Attempts 2 and 3 are marginal micro-variants that do not meaningfully beat it.
- Attempt 1 is therefore selected as the final implementation (copied to `Project/subRay/optimized/final/`).

# Optimization Attempt 3

- Remaining hotspot justification: profiling after Attempt 1 still shows Python call/frame overhead (`call_function`, `_PyEval_MakeFrameVector`, `frame_dealloc`) as a measurable cost in the shading path.
- Why another attempt is justified: the Lambert loop performs a per-light visibility function call (`visible_light`) at each hit point, so removing that hot call boundary is a targeted optimization aligned with observed overhead.
- Exact single change implemented: in `Project/subRay/optimized/attempt3/run_benchmark.py`, the visibility test logic was inlined inside the Lambert lighting loop in `ray_colour()` to avoid per-light `visible_light()` function invocation and associated frame setup/teardown.
- Algorithm preserved: no changes to scene setup, recursion depth, reflection, intersection math, or baseline/original files.

## Attempt 3 Implementation

- Location: `Project/subRay/optimized/attempt3/`
- Files created/updated for this attempt:
	- `Project/subRay/optimized/attempt3/run_benchmark.py`
	- `Project/subRay/optimized/attempt3/pyproject.toml`
	- `Project/subRay/scripts/check_attempt3_correctness.py`

## Correctness Verification

- Command: `python3-dbg scripts/check_attempt3_correctness.py`
- Result file: `Project/subRay/results/attempt3_correctness_report.txt`
- Outcome: `IDENTICAL=YES`
- Matching SHA256:
	- original: `de4b11fd3678d70ba24c3654100970d64bf9d0b8026a18d6fc4d398cdc08057b`
	- attempt3: `de4b11fd3678d70ba24c3654100970d64bf9d0b8026a18d6fc4d398cdc08057b`

## Preliminary Benchmark Note

- An early `--fast` preliminary run was used during development, but its raw result files (`attempt*_fast.txt`) were not retained in the repository.
- The authoritative attempt comparison is the non-fast `perf stat` section above (`Profiling-Based Comparison`).
