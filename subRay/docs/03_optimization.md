# Optimization Attempt 2

- Remaining measured hotspot: attempt1 profiling still shows interpreter dispatch and Python operation overhead as dominant (`_PyEval_EvalFrameDefault`, `binary_op1`, frame alloc/dealloc paths) in [subRay/profiling/perf_report_attempt1.txt](subRay/profiling/perf_report_attempt1.txt).
- Why Attempt 2 is justified: Attempt 1 delivered a major speedup but the remaining top costs are still Python execution overhead, so reducing global/bound lookup work in the hottest loops is a targeted next step.
- Exact planned change: in the Attempt 2 copy only, hoist hot global lookups and helper function references into local variables inside `ray_colour()` and `bench_raytrace()` to reduce repeated name-resolution overhead per pixel and per light.
- Expected benefit: lower interpreter overhead from fewer global lookups and call-site resolution operations in the deepest loops.
- Correctness risk: low to moderate; logic should remain identical, but incorrect rebinding could change control flow or coefficients if done incorrectly.
