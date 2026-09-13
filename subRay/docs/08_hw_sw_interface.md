# Hardware/Software Interface for the Raytrace Intersection Accelerator

Scope: this document explains how software would drive `intersect_accel`
(implemented in `subRay/hw/rtl/`) and what remains proposed/future work.

## Software Side

Which Raytrace function calls the accelerator:
- `ray_colour(px, py, pz, dx, dy, dz, depth, spheres, lights)` — the closest-hit
  scan currently done in a Python `for sphere in spheres` loop plus the
  `halfspace_intersection` plane check. This maps directly to the accelerator's
  `mode=0` (closest-hit) operation.
- `visible_light(px, py, pz, ldx, ldy, ldz, spheres)` — the shadow-ray blocker
  scan. This maps to `mode=1` (visibility) operation.

What data is prepared before a call:
- Ray origin `(px, py, pz)` and normalized direction `(dx, dy, dz)` — already
  computed by Python before the intersection loop runs.
- Scene sphere list `(cx, cy, cz, radius, ...)` and the fixed plane normal
  `(0.0, 1.0, 0.0)` — constant per frame, so they only need to be prepared/loaded
  once, not per ray.
- Conversion of all of the above from Python float to Q16.16 fixed-point
  (`round(x * 65536)`), matching the RTL's numeric format.
- An `epsilon` threshold, matching the software's `EPSILON = 0.00001`.

## Hardware Interface

### IMPLEMENTED (as simulated in `subRay/hw/rtl/intersect_accel.sv`)

Direct RTL port-level interface (no bus/register wrapper exists yet):

- `clk`, `rst_n` — clock and async active-low reset.
- `start` (1-bit in) — pulse to begin one ray's evaluation.
- `mode` (1-bit in) — `0=closest-hit`, `1=visibility`.
- `epsilon` (32-bit in, Q16.16) — validity threshold.
- Ray inputs: `ray_ox/oy/oz`, `ray_dx/dy/dz` (32-bit Q16.16 each).
- Scene inputs: `sph_cx_flat/cy_flat/cz_flat/r_flat` (packed `NUM_SPHERES*32` bits),
  `sph_id_flat` (packed `NUM_SPHERES*8` bits), `plane_nx/ny/nz`, `plane_id`.
- `busy` (1-bit out) — accelerator is processing.
- `done` (1-bit out) — 1-cycle pulse, result valid this cycle.
- Result outputs: `hit_valid`, `hit_kind[1:0]`, `hit_id[7:0]`, `hit_t` (Q16.16),
  `vis_clear`.

This is a functional, testbench-driven interface: the testbench (`tb_intersect_accel.sv`)
drives these ports directly. There is no register map, bus protocol, or DMA engine
implemented — those are proposed below.

### PROPOSED (not implemented, for a real CPU-attached accelerator)

- Memory-mapped register block, e.g.:
  - `CTRL` (offset 0x00): bit0=`start`, bit1=`mode`
  - `STATUS` (offset 0x04): bit0=`busy`, bit1=`done`, bit2=`error`
  - `EPSILON` (offset 0x08)
  - `RAY_OX..RAY_DZ` (offset 0x10-0x24): one register per ray component
  - `HIT_VALID/KIND/ID/T` (offset 0x30-0x3C): result registers
- Input buffer: small on-accelerator scene RAM loaded once per frame (sphere/plane
  parameters), avoiding re-transfer per ray.
- Output buffer: a shallow FIFO of completed hit results, so the CPU can batch-read
  several rays' results instead of polling per ray.
- DMA: for whole-tile ray batches (for example, one scanline of rays), a
  descriptor-based DMA would stream ray inputs in and hit results out, rather than
  one MMIO write per ray.
- `error` status bit: for malformed batch length or buffer underrun (not present
  in the current single-ray RTL, which has no error path).

## Execution Flow

1. CPU prepares input: convert ray origin/direction (and, on first use, the scene)
   from Python float to Q16.16 fixed-point.
2. CPU writes data: place ray fields (and epsilon/mode) into the accelerator's
   input registers (PROPOSED) or drive the RTL ports directly (IMPLEMENTED,
   testbench-only today).
3. CPU starts accelerator: assert `start` for one cycle.
4. Accelerator computes: FSM iterates all spheres through `sphere_intersect`,
   evaluates the plane, and reduces to the nearest valid hit (or blocker, in
   visibility mode). `busy` is high during this time.
5. Accelerator signals completion: `done` pulses for one cycle when the result
   registers (`hit_valid`, `hit_kind`, `hit_id`, `hit_t`, `vis_clear`) are valid.
6. CPU reads result: sample the result outputs/registers and convert `hit_t`
   back from Q16.16 to a Python float before resuming shading logic in
   `ray_colour` / `visible_light`.

## Data Transfer Cost

Why transfer overhead matters here:
- Each ray currently requires only a handful of scalars (6 floats in, ~4-5 values
  out). If each of these crosses a slow interface (for example, one MMIO
  transaction per field over PCIe or a soft-core bus) at microsecond-scale
  latency, the transfer cost can easily exceed the actual compute latency
  (tens of cycles, per the ESTIMATE in `07_hardware_architecture.md`).
- This is the same overhead risk noted in `06_hardware_candidate.md`'s
  "communication overhead" column: single-ray invocation is likely overhead-bound,
  so ray batching (many rays per `start`/`done` handshake) is necessary for the
  accelerator's compute speed to matter end-to-end.
- Loading scene data once per frame (rather than once per ray) is essential:
  spheres/plane are constant across an entire image, so re-sending them per ray
  would dominate transfer cost for no benefit.

## Python Integration

A native wrapper/driver/API would be required; direct Python cannot toggle FPGA
pins or memory-mapped registers on its own. Two realistic options:

- A small C/C++ driver (via `ctypes` or a compiled Python extension module) that
  performs the MMIO reads/writes or DMA setup, exposed to Python as a function
  like `hw_intersect(ox, oy, oz, dx, dy, dz, mode) -> (hit_valid, kind, id, t)`.
- On an FPGA dev board reachable from the host (e.g. via PCIe or a UART/JTAG
  bridge), the driver would additionally handle device discovery, register
  offsets, and any DMA buffer allocation.

Either way, `ray_colour` and `visible_light` would call this wrapper function in
place of their current pure-Python sphere/plane loop, with the fixed-point
conversion happening inside the wrapper so the rest of the benchmark stays
unchanged.

This wrapper/driver layer is entirely PROPOSED; nothing beyond the RTL testbench
interface exists today.

## Block Diagram

```text
+-----------------------------+
| Python: ray_colour() /      |
| visible_light()             |   <- IMPLEMENTED in software today
+---------------+-------------+
                |
                v
+-----------------------------+
| PROPOSED: native wrapper/   |
| driver (ctypes / C ext)     |
| - float -> Q16.16 convert   |
| - MMIO / DMA setup          |
+---------------+-------------+
                |
                v
+-----------------------------+
| PROPOSED: HW/SW register    |
| interface (CTRL/STATUS/     |
| RAY_*/HIT_* registers)      |
+---------------+-------------+
                |
                v
+-----------------------------+
| IMPLEMENTED: intersect_accel|
| RTL ports (start/mode/      |
| epsilon/ray_*/sph_*/plane_*)|
+---------------+-------------+
                |
                v
+-----------------------------+
| IMPLEMENTED: FSM datapath   |
| (sphere_intersect x scene,  |
| plane test, min-reduction)  |
| -- simulated in ModelSim,   |
| all testbench checks pass   |
+---------------+-------------+
                |
                v
+-----------------------------+
| IMPLEMENTED: result outputs |
| (hit_valid/kind/id/t,       |
| vis_clear, done)            |
+---------------+-------------+
                |
                v
+-----------------------------+
| PROPOSED: driver reads      |
| result, converts back to    |
| float                       |
+---------------+-------------+
                |
                v
+-----------------------------+
| Python: resumes ray_colour  |
| shading with hit result     |
+-----------------------------+
```

## Summary: Proposed vs Implemented

IMPLEMENTED:
- `intersect_accel`, `sphere_intersect`, `fxp_sqrt` RTL modules (Q16.16 fixed-point).
- Direct port-level control/status/data interface, exercised by a SystemVerilog
  testbench with a real-valued reference model (see `subRay/hw/tb/`).
- ModelSim simulation with all checks passing (see `subRay/hw/results/`).

PROPOSED (not implemented):
- Memory-mapped register block / bus protocol.
- On-accelerator scene input buffer and output result FIFO.
- DMA for batched ray/result transfer.
- `error` status handling.
- Native Python driver/wrapper (ctypes or C extension) integrating with
  `ray_colour` / `visible_light`.
- Any real host-to-FPGA transport (PCIe, UART/JTAG bridge, etc.).
