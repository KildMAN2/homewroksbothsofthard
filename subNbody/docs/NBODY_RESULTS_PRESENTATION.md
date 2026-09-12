# Nbody Results and Deep Explanation

This note is both a presentation aid and a technical explanation document.

## 1) What nbody is actually doing

The nbody benchmark simulates gravitational interaction among bodies over many timesteps. In each step, the code repeatedly does three expensive categories of work:

- Pairwise force computation between bodies.
- Floating-point arithmetic for distance, inverse-distance, and force scaling.
- Position and velocity updates.

Because those operations are repeated many times, even small per-iteration overhead in Python object handling can dominate total runtime.

## 2) Final measured software result

The authoritative comparison is the controlled staged benchmark in `subNbody/results/optimization_comparison.txt`:

- Original benchmark mean: `4.881335 s`.
- Selected optimization: V1 scalarization.
- V1 mean: `4.381726 s`.
- Speedup: `1.1140x`.
- Improvement: `10.24%`.

V2, V3, V4, and the combined version were measured experiments, but none was selected as the final software optimization. The combined version was slower than the original.

## 3) Historical comparison status

The separate `compare.txt` result is an early preliminary run. It is retained only as historical evidence and must not be used as the final performance result. The final presentation should show only the staged original-versus-V1 values above.

## 4) Profiling evidence from perf

Source files: `subNbody/results/report_original.txt` and `subNbody/results/report_optimized.txt`.

Key observations:

- Original capture: approximately 215K CPU-clock samples, with 0 lost samples.
- V1 capture: approximately 206K CPU-clock samples, with 0 lost samples.
- `_PyEval_EvalFrameDefault`: `30.34%` original and `34.14%` V1 self share.
- `list_subscript.lto_priv.0`: `1.89%` original and `0.01%` V1.
- `PyObject_GetItem`: `1.85%` original and `0.02%` V1.
- `PyObject_SetItem`: `1.87%` original and `1.85%` V1.
- `__ieee754_pow_sse2`: `1.75%` original and `1.92%` V1.

Meaning:

- The runtime is not dominated only by math formulas.
- A major fraction is Python interpreter and object management overhead:
  - dynamic dispatch
  - temporary float creation/destruction
  - repeated indexing and item assignment

V1 directly reduces repeated list reads. Higher percentage shares for remaining functions do not prove that they became slower; they occupy a larger fraction after other work is removed.

## 5) Flamegraph explanation (before and after)

### 5.1 How to read a flamegraph

- Width of a box = cumulative time spent in that function path.
- Height = call stack depth.
- Wide regions near the top of active stacks indicate where most time is consumed.
- Compare flamegraphs by looking for which regions shrink or grow.

### 5.2 Before flamegraph (baseline)

Source file: `subNbody/results/flamegraph_original.svg`.

What to highlight:

- Broad interpreter-related areas show heavy execution in Python frame evaluation.
- Wide arithmetic/object paths indicate repeated float operations and list access overhead.
- The structure matches the perf report hotspots.

### 5.3 After flamegraph (optimized)

Source file: `subNbody/results/flamegraph_optimized.svg`.

The V1 flamegraph shows the list-read paths becoming nearly absent while interpreter, arithmetic, power, and state-write paths remain. This agrees with the measured hotspot percentages and with the source-level scalarization change.

### 5.4 What not to over-claim

- If runtime variance is high, visual shrinkage alone is not enough.
- Flamegraphs explain where time is spent; statistical comparison decides whether speedup is trustworthy.

## 6) Why warnings appeared

You can explain these briefly during Q&A:

- Benchmark instability warning: VM jitter, scheduling noise, and thermal/frequency variation increase variance.
- Kernel symbol warnings from perf: common in VMs with restricted kallsyms; user-space hotspot analysis remains useful.

## 7) Presentation-ready talking points

Use these exact points on your slide:

- Original mean: `4.881335 s`.
- Best software optimization: V1 scalarization at `4.381726 s`.
- Measured software speedup: `1.1140x`, or `10.24%` improvement.
- V2, V3, V4, and the combined version were not selected.
- Profiling confirms that V1 nearly removes repeated list-read paths.
- The corrected RTL was verified separately in simulation and was not connected to Python.

## 8) Short speaking script (60-75 seconds)

"The original Nbody benchmark measured 4.881335 seconds. V1 scalarization reduced repeated Python list reads and measured 4.381726 seconds, giving a 1.1140-times speedup or 10.24 percent improvement. Perf and the flamegraphs confirm that list-read paths nearly disappear, while interpreter and boxed arithmetic costs remain. V2, V3, V4, and the combined version did not outperform V1, so V1 is the selected software result. Separately, I implemented a five-stage Q16.16 accelerator for the true inverse-cube pair calculation and verified it in ModelSim. That RTL was not synthesized or connected to Python, so I do not claim an end-to-end hardware speedup."

## 9) Completed Optimization Results

The variants were measured independently so each change could be evaluated:

| Version | Change | Mean | Improvement | Selected? |
|---|---|---:|---:|---|
| Original | Reference | `4.881335 s` | `0.00%` | Baseline |
| V1 | Scalar local variables | `4.381726 s` | `10.24%` | **Yes** |
| V2 | Unroll 10 body pairs | `4.837512 s` | `0.90%` | No |
| V3 | Explicit sqrt inverse cube | `5.173975 s` | `-6.00%` | No |
| V4 | Precompute `dt*mass` | `4.981543 s` | `-2.05%` | No |
| Combined | V1 through V4 | `5.463925 s` | `-11.94%` | No |

The important conclusion is that optimizations were not additive in CPython. V1 is the final selected software implementation because it was the fastest measured variant and preserved exact behavior in its recorded short correctness test.

## 10) Technical Rationale Per Optimization

### V1: Scalarization

Load values once into local scalars, perform arithmetic locally, then write back once per body. This avoids repeated list access and repeated Python object indirections in hot loops.

### V2: Unroll fixed pairs

With 5 bodies, there are always exactly 10 unique pairs. Explicitly computing these pairs removes per-iteration overhead of pair iteration and tuple unpacking.

### V3: Replace `d2 ** -1.5`

Use:

$$
d2^{-1.5} = \frac{1}{d2\sqrt{d2}}
$$

This is mathematically equivalent, but it measured slower in this CPython environment.

### V4: Precompute constants

Inside one `advance()` call, dt and masses are constant, so compute `dm_i = dt * m_i` once. Reuse `dm_i` in each interaction.

## 11) Correctness Results

- V1 and V2 matched the reference exactly in recorded 100-step checks.
- V3 maximum state difference: `5.551e-17`.
- V4 maximum state difference: `1.110e-16`.
- The combined 20,000-step run had `7.775e-12` maximum position difference against a strict `1e-12` threshold, so its script verdict was FAIL.

The combined version was not selected for either performance or strict numerical agreement.

## 12) Interpreting the Current Nbody Outcome

Current final result:

- Original: `4.881335 s`.
- V1 scalarization: `4.381726 s`.
- Speedup: `1.1140x`.
- Improvement: `10.24%`.

This is a measured software result. It is not evidence of hardware acceleration.

## 13) Final Hardware Accelerator

The final design is `subNbody/hardware/nbody_accel_v2.sv`. The preliminary `nbody_accel_original.sv` is retained only as design-review history and is not the final implementation.

### Interface

Inputs are signed Q16.16 `dx`, `dy`, and `dz`, plus unsigned Q16.16 `mass_i`, `mass_j`, and `dt`. The core returns six signed Q16.16 values: `dvix`, `dviy`, and `dviz` for body i, and `dvjx`, `dvjy`, and `dvjz` for body j.

### Five-stage true-inverse-cube pipeline

1. Compute 64-bit Q32.32 squared distance.
2. Compute integer square root and the 96-bit Q48.48 $d^2\sqrt{d^2}$ denominator.
3. Compute saturated Q16.16 $1/r^3$.
4. Compute the two cross-mass Q48 scales using `dt`, `mass_i`, and `mass_j`.
5. Compute, round, and saturate all six velocity deltas.

Per-stage valid bits and delayed operands keep each transaction aligned. Global backpressure freezes all pipeline state.

### Verification result

- ModelSim compile: `0` errors and `0` warnings.
- Testbench verdict: `NBODY_ACCEL_TEST=PASS transfers=12 latency=5 throughput=1/cycle`.
- Coverage included reset, bubbles, consecutive requests, ordering, backpressure, numerical tolerance, zero distance, and saturation.

The latency and throughput figures are verified RTL simulation behavior only. The design was not synthesized, so no physical clock frequency, area, or power result exists.

## 14) Proposed Hardware Software Integration

```text
Python Nbody -> driver/API -> MMIO/FIFO/DMA -> nbody_accel_v2
             <- velocity deltas for both bodies <-
```

A future interface could batch the 10 unique body-pair records per timestep. Each input record would carry `dx`, `dy`, `dz`, `mass_i`, `mass_j`, and `dt`; each output record would return the two three-axis velocity-delta vectors. Software would merge the 10 outputs in original pair order and retain position updates, energy reporting, and benchmark control.

This interface was not implemented. The RTL was not connected to Python, no FPGA synthesis was performed, and no end-to-end hardware runtime or speedup was measured. Any hardware performance projection must therefore be labeled proposed or estimated.

## 15) Final Evidence Summary

| Category | Result | Status |
|---|---|---|
| Software performance | `4.881335 s` to `4.381726 s`; `1.1140x`; `10.24%` | Measured |
| Selected software | V1 scalarization | Measured and correctness-tested |
| RTL function | True $1/r^3$, both-body deltas, five stages | Verified in simulation |
| RTL handshake | Five-cycle unstalled latency; one transaction/cycle after fill | Verified in simulation only |
| Python/RTL connection | Driver/API plus MMIO/FIFO/DMA | Proposed, not implemented |
| FPGA area, frequency, and power | No values | Not measured |
| End-to-end hardware speedup | No value | Not measured |
