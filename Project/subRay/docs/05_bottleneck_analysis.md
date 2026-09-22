# Bottleneck Analysis

**Project:** subRay HWSW Benchmark Optimization, Analysis, and Hardware Acceleration
**Benchmark:** `raytrace`
**Created:** 2026-09-13
**Status:** Completed
**Deliverable format:** Markdown is the source of truth
**Constraint:** No source code modifications in this analysis step.

## Purpose of This Step

Identify the real bottlenecks in the original `raytrace` benchmark using already saved profiling evidence only.

## Evidence Sources

- `Project/subRay/profiling/perf_report.txt`
- `Project/subRay/profiling/perf_report_supplemental.txt`
- `Project/subRay/profiling/flamegraph_pyspy_baseline.svg`
- `Project/subRay/docs/06_optimization_plan.md`
- `Project/subRay/original/bm_raytrace/run_benchmark.py`

## Hotspot Table

| Rank | Function / Cost Family | Evidence | Why Expensive | Optimization Potential |
|---|---|---|---|---|
| 1 | CPython frame evaluation/dispatch (`_PyEval_EvalFrameDefault`) | `perf_report.txt` shows ~20.63% children / ~20.61% self; `perf_report_supplemental.txt` shows ~23.60% children / ~23.57% self | Core interpreter dispatch executes nearly all Python-level benchmark work repeatedly across pixel, ray, and shading loops | Reduce Python-level operation count in inner loops via scalarization and reduced helper boundaries |
| 2 | Frame creation/deletion (`_PyFrame_New_NoTrack`, `_PyEval_MakeFrameVector`, `frame_dealloc`) | `perf_report.txt`: `_PyFrame_New_NoTrack` ~4.02% children, `_PyEval_MakeFrameVector` ~3.63% self, `frame_dealloc` ~2.41% self; supplemental report also shows frame-dealloc family | High call depth and frequent helper/function boundaries in the ray, shading, and visibility paths create frame churn | Inline/merge hot helper boundaries and avoid unnecessary call layers in inner loops |
| 3 | Python arithmetic and float boxing (`binary_op1`, `PyFloat_FromDouble`) | `perf_report.txt`: `binary_op1` ~2.35% self, `PyFloat_FromDouble` ~1.68% self; supplemental report shows similar families | Vector math and intersection arithmetic in Python induce repeated boxed numeric operations | Use scalar locals and simplified arithmetic paths to reduce object-heavy numeric overhead |
| 4 | Tuple/object access and lookup (`PyTuple_GetItem`, `_PyObject_GetMethod`, `_PyType_Lookup`, dict lookup family) | `perf_report.txt`: `PyTuple_GetItem` ~1.89%, `_PyObject_GetMethod` ~1.70%, `_PyType_Lookup` ~1.29%, plus `lookdict_*`/`_PyDict_GetItemHint`/`insertdict` | Repeated attribute and tuple operations in tight loops amplify dynamic lookup costs | Hoist hot references/aliases to locals and simplify data representation in hot loops |
| 5 | pyperf orchestration and worker control path (baseline py-spy) | `flamegraph_pyspy_baseline.svg` title frames include dominant pyperf stack families (`_main`, `bench_time_func`, `_manager`, `create_worker_bench`, `spawn_worker`, `read_text`) | Benchmark harness overhead appears prominently in stack aggregation and can mask fine-grained application-kernel shapes | Keep this as context; focus optimizations on benchmark inner-kernel work rather than pyperf harness internals |

# Measured Facts

- The saved perf reports consistently show the dominant sampled cost families in interpreter execution and Python object/runtime machinery, not in one isolated native compute symbol.
- Baseline py-spy metadata confirms a direct `python3-dbg ... bm_raytrace/run_benchmark.py --width=64 --height=64` profiling path with `py-spy record --rate 100 --native`.
- Measured official software timing comparison exists and is stable enough for final decision reporting:
  - original: `81.285 +- 0.198 s`
  - final: `19.7062 +- 0.0133 s`
  - improvement: `75.76%`

# Interpretation / Hypotheses

- Because this benchmark is pure Python, many geometric operations appear indirectly as interpreter/frame/lookup costs.
- The repeated ray intersection and shading loops likely drive those interpreter families through high operation frequency.
- Removing object churn and reducing Python call/look-up frequency in inner loops should reduce those measured families, even if perf still labels most cost at interpreter symbols.

# Ranked Optimization Opportunities

Ranking below is aligned with work that was actually performed:

1. Scalarize hot geometry path and reduce object churn in inner loops.
	- Implemented as Attempt 1; selected as final software version.
2. Hoist hot global/helper lookups to locals.
	- Implemented as Attempt 2; correctness passed but slower than Attempt 1.
3. Inline visibility helper in Lambert loop to reduce call/frame overhead.
	- Implemented as Attempt 3; correctness passed but slower than Attempt 1.
4. Additional structural candidates (for future work): remove/streamline temporary intersection containers and further reduce lookup-heavy helper boundaries.

## Activity Log

### 2026-09-13 - Bottleneck analysis completed from existing artifacts

**Before action:** Use only saved profiling evidence and already-created planning docs.

**Actual outcome:** Completed hotspot table, measured-facts section, interpretation section, and ranked opportunities without rerunning profiling.
