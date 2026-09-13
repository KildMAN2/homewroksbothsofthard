# Hardware Architecture: Raytrace Intersection Accelerator (Design Only)

## Accelerator Purpose

Accelerate the selected kernel from Step 06:
- sphere/plane intersection testing
- nearest-hit reduction
- shadow-ray visibility intersection checks

Goal:
- remove large amounts of repeated scalar geometry arithmetic from Python software
- keep control-heavy shading recursion in software

This document is architecture-only. No RTL is implemented here.

## Inputs

Interface style (proposed): batched command/response over memory-mapped control + streaming/buffered ray jobs.

### Control Inputs

- `start` : begin processing a submitted batch : 1 bit
- `mode` : `0=closest_hit`, `1=visibility_only` : 1 bit
- `batch_count` : number of rays in current batch : 16 bits
- `epsilon` : intersection threshold : 32 bits (FP32)
- `scene_obj_count` : number of sphere records used : 8 bits

### Per-Ray Inputs

- `ray_id` : software correlation tag : 32 bits
- `ray_origin_x` : ray origin x : 32 bits (FP32)
- `ray_origin_y` : ray origin y : 32 bits (FP32)
- `ray_origin_z` : ray origin z : 32 bits (FP32)
- `ray_dir_x` : normalized direction x : 32 bits (FP32)
- `ray_dir_y` : normalized direction y : 32 bits (FP32)
- `ray_dir_z` : normalized direction z : 32 bits (FP32)

### Scene/Object Inputs

Spheres stored in on-accelerator parameter RAM (loaded once per frame/scene):
- `sphere_cx` : center x : 32 bits (FP32)
- `sphere_cy` : center y : 32 bits (FP32)
- `sphere_cz` : center z : 32 bits (FP32)
- `sphere_r` : radius : 32 bits (FP32)
- `sphere_id` : object ID for hit reporting : 8 bits

Plane parameters (constant for current benchmark halfspace):
- `plane_nx` : plane normal x : 32 bits (FP32)
- `plane_ny` : plane normal y : 32 bits (FP32)
- `plane_nz` : plane normal z : 32 bits (FP32)
- `plane_id` : plane object ID : 8 bits

## Outputs

### Status Outputs

- `done` : batch complete : 1 bit
- `busy` : accelerator active : 1 bit
- `error` : protocol/range error : 1 bit

### Per-Ray Outputs

- `ray_id_out` : echoed correlation tag : 32 bits
- `hit_valid` : nearest valid hit exists : 1 bit
- `hit_kind` : `0=none,1=sphere,2=plane` : 2 bits
- `hit_obj_id` : sphere/plane ID : 8 bits
- `hit_t` : nearest positive intersection distance : 32 bits (FP32)
- `visibility_clear` : for visibility mode, `1=no blocker`, `0=blocked` : 1 bit

## Numeric Representation

Chosen representation: floating-point for geometry datapath.

- Type: FP32 (IEEE-754 single precision) for all geometric inputs/outputs.
- Why not integer: ray/sphere equations require fractional values and wide dynamic range.
- Why not fixed-point first: fixed-point would reduce area/power, but increases scaling risk around sqrt/discriminant and can require per-scene retuning.
- Why FP32 over FP64: lower area and higher throughput than FP64; expected adequate image quality for this benchmark class.

Assumption note:
- Software currently uses Python float semantics (effectively double precision). Any FP32 adoption should be validated against image-difference tolerance in a later verification step.

## Datapath

Per sphere, compute intersection of ray `P + tD` with sphere center `C`, radius `r`.

Execution order:
1. `CP = C - P` (3 subtracts)
2. `v = dot(CP, D)` (3 mul + 2 add)
3. `cp2 = dot(CP, CP)` (3 mul + 2 add)
4. `disc = r*r - (cp2 - v*v)` (3 mul + 2 add/sub)
5. If `disc < 0`, reject sphere.
6. `sqrt_disc = sqrt(disc)`
7. `t = v - sqrt_disc`
8. Valid if `t > epsilon` (or `>-epsilon` depending mode policy mirrored from software caller).
9. Feed valid `t` into min-reduction tree/register: keep smallest positive `t` and corresponding `obj_id`.
10. Plane intersection in parallel path:
   - `projection = dot(D, N)`
   - if `projection != 0`, `t_plane = 1 / -projection`
   - valid test then merge into same min-reduction.

Visibility mode:
- same sphere/plane test path
- early-exit allowed when first blocker with `t > epsilon` is found

## Control Logic

Proposed FSM:
- `IDLE`: wait for `start`
- `LOAD_SCENE`: optional scene RAM load/validate (or skipped if already loaded)
- `FETCH_RAY`: pull one ray job
- `SPHERE_LOOP`: iterate sphere table index
- `PLANE_TEST`: evaluate plane candidate
- `REDUCE_FINAL`: finalize nearest hit / visibility flag
- `WRITE_RESULT`: push output tuple
- `NEXT_RAY`: decrement counter, continue or finish
- `DONE`: raise `done`, return to `IDLE`

Control features:
- separate mode bit for `closest_hit` vs `visibility_only`
- optional early-exit in visibility mode to reduce average latency
- watchdog/error path for invalid batch length or buffer underrun

## Pipeline

Proposed pipeline stages (single sphere lane):
1. `S0` Input/parameter read
2. `S1` Vector subtract `CP`
3. `S2` Dot products partials
4. `S3` Dot reductions and discriminant precompute
5. `S4` `disc` finalize + sign check
6. `S5` Sqrt
7. `S6` `t` compute + validity check
8. `S7` Min-reduction/update state

Plane path can be pipelined similarly and merged at reduction stage.

## Parallelism

Two independent dimensions:
- Object-level parallelism: process multiple spheres concurrently (multi-lane sphere units)
- Ray-level parallelism: multiple in-flight rays if buffering supports it

Practical first design:
- 2 or 4 sphere lanes sharing one control front-end and reduction network
- one plane unit in parallel with sphere lanes

Simultaneous operations:
- while lane A computes sqrt for sphere i, lane B can compute dot products for sphere i+1
- result writeback for ray n can overlap input fetch for ray n+1

## Latency

All values below are ESTIMATE (not measured, not synthesized).

Let:
- `Lpipe` = fixed pipeline fill/drain overhead (about 10-16 cycles estimated)
- `Lsphere` = effective cycles per sphere candidate per lane after pipeline full (about 1 cycle/candidate/lane estimated)
- `N` = sphere count (7 in current benchmark)
- `K` = number of sphere lanes

Closest-hit per ray ESTIMATE:
- `Latency_cycles ≈ Lpipe + ceil(N / K) + Lplane + Lreduce`
- with `K=2`: about `16 + 4 + 3 + 2 = 25 cycles`
- with `K=4`: about `16 + 2 + 3 + 2 = 23 cycles`

Visibility mode ESTIMATE:
- worst-case similar to closest-hit
- average-case lower if early blocker triggers early-exit

## Throughput

All values below are ESTIMATE.

Steady-state, per cycle:
- sphere-candidate throughput about `K` candidates/cycle after fill
- ray-result throughput depends on ray/object ratio and control overhead

For small fixed scene (7 spheres), expected sustained output rate:
- roughly one completed ray every about 6-12 cycles (K=2..4), ignoring host I/O stalls

## Clock Frequency

ESTIMATE only (no synthesis data):
- target clock: 150-250 MHz on moderate FPGA with pipelined FP32 units
- conservative planning value: 200 MHz ESTIMATE

At 200 MHz and 10 cycles/ray effective average:
- about 20 million ray-results/second theoretical datapath ceiling (before interface/software limits)

## Hardware/Software Boundary

Moves to hardware:
- sphere intersection math
- plane intersection math
- nearest-hit reduction
- visibility blocker test

Remains in software (Python/C side wrapper):
- scene construction and material setup
- recursion flow in `ray_colour`
- shading composition (Lambert/specular/ambient)
- image buffer writes and final file output
- scheduling of ray batches and command submission

Boundary rationale:
- keep complex dynamic control and Python-level orchestration in software
- offload dense, repetitive arithmetic kernel to accelerator

## Block Diagram

```text
+------------------+
|   CPU / Python   |
| ray generation & |
| shading control  |
+---------+--------+
          |
          v
+--------------------------+
| HW/SW Interface          |
| MMIO control + DMA/queue |
+-----------+--------------+
            |
            v
+--------------------------+
| Input Buffer (Ray Batch) |
+-----------+--------------+
            |
            v
+-----------------------------------------------+
| Intersection Accelerator Datapath             |
|                                               |
| +-------------------+   +-------------------+ |
| | Sphere Lane 0     |   | Sphere Lane 1..K  | |
| | CP,dot,disc,sqrt  |   | CP,dot,disc,sqrt  | |
| +---------+---------+   +---------+---------+ |
|           \                 /                 |
|            \               /                  |
|          +-----------------------+            |
|          | Min-Reduction /       |            |
|          | Visibility Decision   |            |
|          +-----------+-----------+            |
|                      |                        |
|             +--------v--------+               |
|             | Plane Unit      |               |
|             | dot,reciprocal  |               |
|             +-----------------+               |
+-------------------+---------------------------+
                    |
                    v
+--------------------------+
| Output Buffer (Hit Data) |
+-----------+--------------+
            |
            v
+------------------+
|   CPU / Python   |
| continue shading |
+------------------+
```

## Tradeoffs

Performance:
- Strong benefit potential from batching and pipelined arithmetic.
- Real gain depends on HW/SW transfer efficiency and software integration overhead.

Area:
- FP32 sqrt/div and multi-lane units consume notable DSP/LUT/BRAM resources.
- More lanes increase throughput but scale area.

Power:
- Higher than software-only control path, especially with multiple active FP units.
- Can be controlled via clock gating and lane count selection.

Precision:
- FP32 may introduce small numeric differences versus software FP64 behavior.
- Must be validated with image/correctness tolerance tests before final adoption.

Complexity:
- Moderate system complexity: interface, buffering, reduction logic, and software driver integration.
- Still simpler than moving full recursive shading control into hardware.

# RTL Implementation Plan

## Numeric Format Decision for RTL v1

The architecture selected FP32 as the ideal representation. For the first synthesizable
RTL implementation, the datapath is built in **signed fixed-point Q16.16** instead of
full IEEE-754 FP32. Reason:

- A complete, correct IEEE-754 FP32 multiply/add/sqrt core is a large subproject and would
  dominate this step.
- Q16.16 provides real, synthesizable arithmetic (no FP library dependency) and is adequate
  for the benchmark scene coordinate range (roughly |coord| < ~200).
- This is an explicit, documented deviation from the FP32 target. FP32 remains the longer-term
  representation once numeric tolerance is validated.

All fixed-point scaling assumptions are documented in the RTL comments.

## Module Hierarchy

```
intersect_accel        (top: FSM, scene iteration, min-reduction, plane test)
 ├── sphere_intersect  (per-sphere t computation, discriminant + sqrt)
 │    └── fxp_sqrt      (iterative integer square root, 64-bit radicand)
 └── (plane reciprocal via fixed-point division inside top)
```

## Parameters

- `WIDTH` = 32 (fixed-point word width)
- `FRAC`  = 16 (fractional bits, Q16.16)
- `NUM_SPHERES` = scene sphere count (parameterized; TB uses a small scene)
- `MODE`: runtime input bit (0 = closest-hit, 1 = visibility-only)

## Clock / Reset

- Single clock `clk`, positive-edge triggered.
- Asynchronous active-low reset `rst_n`.
- All sequential state in `always_ff @(posedge clk or negedge rst_n)`.

## Ports (top `intersect_accel`)

- Control: `clk`, `rst_n`, `start`, `mode`, `epsilon` (Q16.16)
- Ray: `ray_ox/oy/oz`, `ray_dx/dy/dz` (Q16.16 signed)
- Scene (flattened packed vectors, sliced by index):
  `sph_cx_flat`, `sph_cy_flat`, `sph_cz_flat`, `sph_r_flat`, `sph_id_flat`
- Plane: `plane_nx/ny/nz` (Q16.16), `plane_id`
- Outputs: `done`, `busy`, `hit_valid`, `hit_kind[1:0]`, `hit_id[7:0]`,
  `hit_t` (Q16.16), `vis_clear`

## Datapath Modules

- `sphere_intersect`: computes `CP = C - P`, `v = dot(CP,D)`, `cp2 = dot(CP,CP)`,
  `disc = r^2 - cp2 + v^2`, rejects if `disc < 0`, else `t = v - sqrt(disc)` and
  validity vs threshold. Intermediate products held in Q32.32 (64-bit) for precision.
- `fxp_sqrt`: 32-iteration digit-by-digit integer square root; input is the Q32.32
  discriminant, output is Q16.16 root (scaling proven in comments).
- Plane path (in top): `proj = dot(D,N)`, `t_plane = 1 / (-proj)` via fixed-point division.

## Control / FSM

- `sphere_intersect` FSM: `IDLE -> CALC -> SQRT -> DONE`.
- `intersect_accel` FSM: `IDLE -> SPH_START -> SPH_WAIT (loop over spheres)
  -> PLANE -> FIN -> IDLE`, with min-reduction updated on each valid candidate.

## Pipeline Stages

- RTL v1 is iterative (multi-cycle per sphere) because `fxp_sqrt` is a 32-cycle unit.
- This favors correctness and low area over full throughput.
- The architecture's deeper pipeline (parallel sphere lanes, streaming) is future work
  and is noted rather than implemented here.

# RTL Results

## Files

RTL (`subRay/hw/rtl/`):
- `fxp_sqrt.sv` — iterative 32-cycle integer square root.
- `sphere_intersect.sv` — per-sphere Q16.16 intersection (discriminant + sqrt).
- `intersect_accel.sv` — top FSM: scene iteration, plane test, min-reduction.

Testbenches (`subRay/hw/tb/`):
- `tb_fxp_sqrt.sv` — self-checking, exact integer comparison.
- `tb_intersect_accel.sv` — self-checking, real-valued reference model with tolerance.

Simulation artifacts (`subRay/hw/results/`):
- `compile.log`, `sim_fxp_sqrt.log`, `sim_intersect_accel.log`, `SIMULATION_RESULTS.txt`.

## Simulator

- ModelSim - Intel FPGA Edition, vlog/vsim 10.5b (2016.10), run locally on Windows.
- Compilation: 0 errors, 0 warnings.

## Measured Simulation Outcome (actually ran)

- `tb_fxp_sqrt`: checks=11, errors=0, "SQRT RESULT: ALL PASS".
- `tb_intersect_accel`: checks=7, errors=0, "ACCEL RESULT: ALL PASS".

Accelerator cases that passed:
- direct sphere hit (t=8.000000, exp 8.000000)
- plane-only hit (t=1.000000, exp 1.000000)
- ray escapes / no-hit
- off-axis small-component direction (t=9.414810, exp 9.413574, within 0.05 tol)
- side sphere hit (t=9.000000, exp 9.000000)
- visibility mode blocked (vis_clear=0)
- visibility mode clear (vis_clear=1)

## Honest Limitations

- Numeric datapath is Q16.16 fixed-point, not IEEE-754 FP32 (documented deviation).
- RTL v1 is iterative (multi-cycle per sphere), not the fully pipelined multi-lane
  design described in the architecture.
- No synthesis was performed. No area, clock-frequency, or power numbers are claimed;
  the earlier frequency/latency/throughput figures remain ESTIMATE only.

## Scope Boundary

No synthesis numbers are claimed.
RTL and testbench are provided under `subRay/hw/` from this step onward.
