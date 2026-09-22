# Hardware Performance Estimate (Raytrace Intersection Accelerator)

**All numbers in this document are ESTIMATES unless explicitly labeled MEASURED.**
No synthesis, no FPGA bring-up, and no hardware-in-the-loop timing exists yet.
Nothing here should be read as measured hardware performance.

## Measured Inputs Used

MEASURED (software, official full pyperformance run, non-`--fast`):
- Original mean: `81.285 s` (± `0.198 s`) — `Project/subRay/results/original_official.txt`
- Final (software-optimized) mean: `19.7062 s` (± `0.0133 s`) — `Project/subRay/results/final_official.txt`
- Official software-only improvement already banked: `75.76%`

MEASURED (perf sampling, `Project/subRay/profiling/perf_report.txt` and
`perf_report_supplemental.txt`), used only to justify the P range below, not as a
precise isolated kernel measurement:
- `_PyEval_EvalFrameDefault`: ~20.6%–23.6% of sampled `cpu-clock`
- `binary_op1`: ~1.8%–2.4%
- `_PyEval_MakeFrameVector` / `frame_dealloc`: ~2.4%–3.6% combined
- `PyFloat_FromDouble`, `PyTuple_GetItem`: ~1.1%–1.9% each

These samples land in interpreter/object machinery, not in a single named
"intersection" symbol, because the benchmark is pure Python. They are consistent
with — but do not directly isolate — the intersection kernel selected in
`Project/subRay/docs/06_hardware_candidate.md`.

## Original Hotspot Fraction

There is no clean, isolated measurement of "percent of runtime spent only in
sphere/plane intersection math" because Python does not attribute samples to a
single fused kernel the way compiled code would — the same intersection logic is
smeared across interpreter dispatch, float boxing, tuple access, and frame churn
samples above.

Per `Project/subRay/docs/06_hardware_candidate.md`, the accelerated fraction `P` is
therefore an **assumed range, not a direct measurement**:
- `P_low = 0.40`
- `P_mid = 0.50` (used as the realistic case below)
- `P_high = 0.70` (used as the optimistic case below)

This range is derived from operation-frequency reasoning (7 spheres + 1 plane,
tested up to ~21+3 times per shaded hit point, across up to 4 recursion levels)
combined with the measured interpreter/numeric hotspot evidence above — not from
an isolated stopwatch measurement of the kernel alone. **ESTIMATE.**

## Assumed Accelerator Throughput

ESTIMATE, carried from `Project/subRay/docs/07_hardware_architecture.md` (RTL-latency
model, not synthesized, not measured on real hardware):
- ~23–25 cycles per ray for closest-hit against the current 7-sphere + 1-plane
  scene, with `K=2..4` sphere lanes (architecture doc's pipelined design; the
  RTL actually simulated in `Project/subRay/hw/rtl/` is the simpler iterative v1, which
  is slower per ray — see "Accelerator Utilization" below).
- At the assumed clock rate (next section), this gives a **datapath-only**
  ceiling of about 20 million ray-evaluations/second, before any host transfer
  cost is added.

## Communication / Transfer Overhead

ESTIMATE, not measured:
- Each ray needs 6 input floats (origin + direction) and produces ~5 output
  fields (valid/kind/id/t/vis_clear) — roughly 24–44 bytes per ray depending on
  packing.
- If each ray is submitted as a single unbatched register write/read over a
  typical MMIO-style link, a round trip on the order of hundreds of
  nanoseconds to a few microseconds per call is a reasonable planning
  assumption. That is comparable to, or larger than, the ~50–125 ns compute
  time estimated above.
- Consequence: **without batching, transfer overhead can equal or exceed
  compute time**, driving effective speedup toward 1x or worse. This is why
  `Project/subRay/docs/06_hardware_candidate.md` and `08_hw_sw_interface.md` both call
  out ray-batching / DMA as a requirement, not an optional optimization.
- The "realistic" Amdahl case below assumes partial (not perfect) batching, so
  overhead is not eliminated, only reduced.

## Assumed Clock Rate

ESTIMATE only (explicitly labeled per `07_hardware_architecture.md`; no synthesis
was run):
- Planning value: **200 MHz ESTIMATE** on a moderate FPGA target.

## Amdahl's Law Model

```
Speedup = 1 / ((1 - P) + P/S)
```
- `P` = fraction of the FINAL software runtime attributed to the accelerated
  intersection kernel (assumption, see above).
- `S` = speedup of that accelerated section only (compute + realistic transfer
  overhead combined into one effective factor).

### Optimistic Estimate — ESTIMATE

- `P = 0.70` (upper end of the assumed range)
- `S = 100` (assumes aggressive batching/DMA makes transfer overhead nearly
  negligible relative to compute, i.e. close to the raw datapath ceiling)

```
Speedup = 1 / ((1 - 0.70) + 0.70/100)
        = 1 / (0.30 + 0.007)
        = 1 / 0.307
        ≈ 3.26x   ESTIMATE
```

### Realistic Estimate — ESTIMATE

- `P = 0.50` (middle of the assumed range, more conservative than the
  optimistic case)
- `S = 8` (assumes only moderate batching; per-call transfer overhead still
  eats a meaningful share of the raw compute win)

```
Speedup = 1 / ((1 - 0.50) + 0.50/8)
        = 1 / (0.50 + 0.0625)
        = 1 / 0.5625
        ≈ 1.78x   ESTIMATE
```

### Theoretical Maximum (S -> infinity), for context — ESTIMATE

- `P = 0.70` -> max speedup = `1 / (1 - 0.70) ≈ 3.33x`
- `P = 0.50` -> max speedup = `1 / (1 - 0.50) = 2.00x`

No amount of accelerator speed can exceed these ceilings while `P` stays fixed;
this is the Amdahl ceiling, not a hardware capability claim.

## Software Time Remaining — ESTIMATE

Base: MEASURED final software mean `19.7062 s`.

| Case        | P    | S   | Non-accelerated time (fixed) | Accelerated-section time | Total ESTIMATE | Speedup ESTIMATE |
|-------------|------|-----|-------------------------------|---------------------------|-----------------|-------------------|
| Optimistic  | 0.70 | 100 | `0.30 x 19.7062 = 5.91 s`      | `0.70 x 19.7062/100 = 0.14 s` | `6.05 s`   | `3.26x`           |
| Realistic   | 0.50 | 8   | `0.50 x 19.7062 = 9.85 s`      | `0.50 x 19.7062/8 = 1.23 s`   | `11.08 s`  | `1.78x`           |

The non-accelerated portion (`1-P` of the final software time) is a hard floor:
it does not shrink no matter how fast the accelerator is, because it represents
software work (shading composition, recursion control, image I/O, and Python
overhead unrelated to the offloaded kernel) that stays on the CPU.

## Area Impact — ESTIMATE / qualitative

- Multiple FP/fixed-point lanes (sqrt units especially) are DSP/LUT-heavy;
  `Project/subRay/docs/07_hardware_architecture.md` already flags sqrt/div and
  multi-lane replication as the main area drivers.
- More sphere lanes (`K`) trade area for lower per-ray latency; no synthesis
  has been run, so no LUT/DSP/BRAM counts can be stated.

## Power Impact — ESTIMATE / qualitative

- More active lanes and higher clock both increase dynamic power.
- No power measurement or synthesis-based estimate exists; only the qualitative
  direction (more parallelism/clock -> more power) can be stated honestly.

## Memory Bandwidth Limits — ESTIMATE

- At the ~20M rays/sec datapath ceiling and ~24–44 bytes/ray, sustained ray
  traffic alone would need on the order of **0.5–0.9 GB/s** of host-to-device
  bandwidth to keep the datapath fed. This is a back-of-envelope ESTIMATE, not
  a measured or platform-specific number.
- Scene data (7 spheres + plane) is tiny and only needs to be sent once per
  frame, so it is not a bandwidth concern; per-ray traffic is the bottleneck to
  watch.
- If the real transport (PCIe/UART/JTAG bridge, per `08_hw_sw_interface.md`,
  all still PROPOSED) cannot sustain that rate, the accelerator will be
  bandwidth-bound rather than compute-bound, reinforcing the need for batching.

## Precision Tradeoffs

- The RTL actually implemented and simulated (`Project/subRay/hw/rtl/`) uses Q16.16
  fixed-point, not the FP32 originally proposed in the architecture doc — a
  documented deviation, verified only against a fixed-point reference model in
  simulation (see `Project/subRay/hw/results/`), not against the real Python/FP64
  benchmark output.
- Any accuracy claim against the actual raytrace image would require a
  correctness/tolerance comparison that has not been performed. This document
  makes no such claim.

## Accelerator Utilization — ESTIMATE / qualitative

- The RTL simulated so far is the **iterative v1** design (one sphere at a
  time through a shared `sphere_intersect` unit with a 32-cycle sqrt), not the
  multi-lane pipelined design assumed for the throughput numbers above. Its
  actual per-ray cycle count is dominated by the 32-cycle `fxp_sqrt` loop times
  up to 7 spheres, i.e. noticeably higher than the ~23–25 cycle pipelined
  ESTIMATE used in the Amdahl model.
- This means the throughput/S values used above describe the **target
  architecture**, not the exact RTL currently simulated. Closing that gap
  (adding lanes, pipelining `fxp_sqrt` calls) is future work, not yet built.

## Transfer Overhead (recap)

- Per-ray MMIO-style handshakes are the single biggest risk to realizing any of
  the above speedups; see "Communication / Transfer Overhead" above.
- The realistic case (`S=8`) already prices in partial overhead; the optimistic
  case (`S=100`) assumes it is engineered away via batching/DMA, which is
  PROPOSED, not implemented.

## Summary

- All speedup, throughput, clock, latency, area, power, and bandwidth figures
  in this document are **ESTIMATE**.
- Only the two official mean runtimes (`81.285 s` original, `19.7062 s` final)
  and the perf sample percentages are MEASURED.
- Optimistic ESTIMATE speedup over the current FINAL software version: **~3.26x**
- Realistic ESTIMATE speedup over the current FINAL software version: **~1.78x**
- These are theoretical/planning figures only; no hardware-in-the-loop
  measurement has been performed.

## Evidence Boundary Labels

- MEASURED SOFTWARE:
  - `Project/subRay/results/original_official.txt`
  - `Project/subRay/results/final_official.txt`
  - saved perf sample percentages in `Project/subRay/profiling/perf_report.txt` and `Project/subRay/profiling/perf_report_supplemental.txt`
- IMPLEMENTED RTL:
  - `Project/subRay/hw/rtl/fxp_sqrt.sv`
  - `Project/subRay/hw/rtl/sphere_intersect.sv`
  - `Project/subRay/hw/rtl/intersect_accel.sv`
- SIMULATED RTL:
  - `Project/subRay/hw/results/compile.log`
  - `Project/subRay/hw/results/sim_fxp_sqrt.log`
  - `Project/subRay/hw/results/sim_intersect_accel.log`
  - `Project/subRay/hw/results/SIMULATION_RESULTS.txt`
- ESTIMATED HARDWARE:
  - all Amdahl speedups, throughput, cycle, bandwidth, clock, area, and power values in this document
- PROPOSED SYSTEM INTEGRATION:
  - register map, buffering, DMA, and Python driver/wrapper flow in `Project/subRay/docs/08_hw_sw_interface.md`
