# Nbody Final Presentation Notes

These notes use only measured project results, recorded simulation results, and clearly labeled estimates. The strongest software result is V1 scalarization. The SystemVerilog accelerator was verified independently in simulation but was not connected to Python or synthesized.

## Presentation Rule

Keep these evidence categories separate on every slide:

- **Measured software:** pyperformance timing and Linux perf sampling from executed Python programs.
- **Verified RTL simulation:** functional, latency, throughput, and backpressure behavior observed in ModelSim.
- **Proposed or estimated:** HW/SW integration, synthesis characteristics, and potential end-to-end hardware speedup.

Do not describe simulated RTL throughput as measured application acceleration.

## Slide 1: Nbody Algorithm

### What the slide should show

- A five-body diagram labeled Sun, Jupiter, Saturn, Uranus, and Neptune.
- The 10 unique unordered body pairs.
- The pair-update equations:

$$
d^2 = dx^2 + dy^2 + dz^2
$$

$$
inv\_r^3 = \frac{1}{d^2\sqrt{d^2}}
$$

$$
\Delta v_i = -\Delta r\,(dt\,m_j\,inv\_r^3), \qquad
\Delta v_j = +\Delta r\,(dt\,m_i\,inv\_r^3)
$$

- A short loop structure: 20,000 timesteps, 10 pair interactions per timestep, then five position updates.

### What I should say

"The benchmark simulates five solar-system bodies. Each timestep processes the 10 unique body pairs, so no self-interaction or duplicate pair is computed. For each pair, the code forms the displacement, calculates inverse distance cubed, and applies opposite velocity updates. Body i uses body j's mass, and body j uses body i's mass. After all pair forces are accumulated, the five positions are updated. The default workload keeps the original 20,000 iterations."

### Result to emphasize

The repeated pair kernel is structurally regular: 10 executions per timestep and 200,000 pair evaluations per benchmark advance call. That repetition makes it relevant to both software optimization and pipelined hardware.

### Likely instructor questions

**Why are there 10 pairs instead of 25?**

There are $\binom{5}{2}=10$ unique unordered pairs. Processing each pair once updates both bodies and avoids duplicate work.

**Why is the force term $1/r^3$ rather than $1/r^2$?**

The scalar gravitational magnitude contains $1/r^2$, but the code multiplies by the displacement vector $\Delta r$. Writing the vector update directly as $\Delta r/r^3$ supplies both direction and magnitude.

## Slide 2: Baseline and Measurement Method

### What the slide should show

- Environment: Ubuntu 22.04 QEMU VM, Python 3.10.12 debug build, four logical CPUs.
- Tool: pyperformance using `python3-dbg`.
- Workload: unchanged default 20,000 iterations.
- Primary baseline: `4.881335 s`.
- A small warning box: several benchmark runs were noisy, so small differences are interpreted cautiously.

### What I should say

"I measured all optimization stages using the same debug Python and pyperformance environment, without reducing the workload or introducing native libraries. The authoritative staged baseline was 4.881335 seconds. A separate early comparison artifact was preliminary and is not used as the final result. I therefore use the controlled six-version staged table and select the fastest measured variant from that comparison."

### Result to emphasize

The baseline for the final optimization comparison is `4.881335 s`. Do not mix it with the separate preliminary comparison artifact when calculating or presenting the final speedup.

### Likely instructor questions

**Why use `python3-dbg` rather than normal Python?**

The project environment and perf-symbol analysis used the debug interpreter consistently for baseline and optimized versions. It is slower than a release build, but the comparison remains controlled because every staged version used the same interpreter.

**Are the results statistically definitive?**

No. Several pyperformance runs were flagged as unstable. V1 had the strongest measured difference in this run set, but additional isolated reruns would be needed for a high-confidence general performance claim.

## Slide 3: Perf and Flame Graph Evidence

### What the slide should show

- Side-by-side images:
  - `subNbody/results/flamegraph_original.svg`
  - `subNbody/results/flamegraph_optimized.svg`
- Capture facts:
  - Original: approximately 215K CPU-clock samples.
  - V1: approximately 206K CPU-clock samples.
  - Sampling frequency: 499 Hz.
  - Lost samples: 0 for both.
- A small hotspot table:

| Self hotspot | Original | V1 scalar |
|---|---:|---:|
| `_PyEval_EvalFrameDefault` | 30.34% | 34.14% |
| `PyFloat_FromDouble` | 6.09% | 6.26% |
| `binary_op1` | 5.80% | 6.15% |
| `list_subscript.lto_priv.0` | 1.89% | 0.01% |
| `PyObject_GetItem` | 1.85% | 0.02% |
| `PyObject_SetItem` | 1.87% | 1.85% |
| `__ieee754_pow_sse2` | 1.75% | 1.92% |

### What I should say

"Perf and the flame graphs show that the benchmark is not only doing physical arithmetic. A large share is CPython interpreter dispatch, boxed-float handling, and list access. After V1 scalarization, the list-read paths nearly disappear: `list_subscript` falls from 1.89 percent to 0.01 percent, and `PyObject_GetItem` falls from 1.85 percent to 0.02 percent. The arithmetic, power, and final list-write paths remain."

### Result to emphasize

V1 affected exactly the profile paths it targeted. The strongest evidence is the near-removal of list-read self time, not the increase in percentage share of remaining interpreter functions.

### Likely instructor questions

**Why did `_PyEval_EvalFrameDefault` rise from 30.34% to 34.14% if V1 is faster?**

These are shares of different total runtimes, not absolute function times. Removing list-read work makes unchanged costs occupy a larger percentage of the shorter execution.

**Did the QEMU kernel-symbol warning invalidate the profile?**

No. Kernel symbols were restricted, but the relevant Python user-space symbols resolved, and both captures had zero lost samples.

## Slide 4: Identified Bottleneck

### What the slide should show

A highlighted original pair-update pseudocode block with these costs labeled:

- repeated `v[0]`, `v[1]`, and `v[2]` list accesses,
- Python binary-operation dispatch,
- temporary float creation and destruction,
- `d2 ** (-1.5)`,
- repeated pair arithmetic.

### What I should say

"The bottleneck is a mixed software cost. The mathematical kernel is repeated, but CPython represents every arithmetic result as an object and dispatches generic operations. The original loop also repeatedly reads velocity elements from Python lists. The first optimization therefore targeted object and indexing overhead without changing the pair order or force expression."

### Result to emphasize

Profiling led directly to V1 scalarization. This is a profile-driven change, not an assumed micro-optimization.

### Likely instructor questions

**Is the power function the largest bottleneck?**

No. `__ieee754_pow_sse2` is visible at 1.75% original self time, but interpreter dispatch, float object operations, and list handling collectively occupy more of the profile.

**Why not use NumPy or Numba?**

The software optimization requirement was pure Python. NumPy or Numba would change the implementation model and make it difficult to attribute gains to the staged Python transformations.

## Slide 5: Software Optimization Ladder

### What the slide should show

| Version | Change | Mean time | Improvement |
|---|---|---:|---:|
| Original | Reference implementation | 4.881335 s | 0.00% |
| V1 | Scalar local variables | 4.381726 s | 10.24% |
| V2 | Unroll 10 fixed pairs | 4.837512 s | 0.90% |
| V3 | Explicit sqrt inverse cube | 5.173975 s | -6.00% |
| V4 | Precompute `dt*mass` | 4.981543 s | -2.05% |
| Combined | V1 through V4 | 5.463925 s | -11.94% |

Use a bar chart if time allows, with a horizontal baseline at 4.881335 seconds.

### What I should say

"I evaluated changes independently instead of assuming they would compose. V1 loads list values into local scalars and writes back once. V2 expands all 10 pair blocks. V3 replaces the power form with explicit square root and division. V4 precomputes timestep-times-mass constants. Only V1 produced a clear improvement in this measurement set. Unrolling increases interpreted code volume, and mathematically simpler expressions are not automatically faster in CPython."

### Result to emphasize

Optimization effects were not additive. The final combined implementation was slower than the original, so the selected optimized implementation is V1, not the file named `run_benchmark_optimized.py`.

### Likely instructor questions

**Why did loop unrolling barely help?**

It removes loop and tuple-unpacking work but greatly expands the interpreted instruction stream. In CPython, instruction dispatch and code size can offset the saved loop overhead.

**Why did replacing power with square root regress?**

Equivalent mathematics does not imply equivalent CPython cost. The explicit form adds Python-level multiplication and division around `sqrt`, while the original power operation enters optimized C library code.

## Slide 6: Software Speedup and Correctness

### What the slide should show

Large central result:

```text
4.881335 s -> 4.381726 s
1.1140x speedup
10.24% improvement
```

Correctness box:

- V1 short test: exact state and energy agreement at 100 steps.
- V2: exact short-run agreement.
- V3 maximum difference: `5.551e-17`.
- V4 maximum difference: `1.110e-16`.
- Combined 20,000-step maximum position difference: `7.775e-12` against a `1e-12` threshold, so its script verdict is FAIL.

### What I should say

"The best measured software result is V1: 4.381726 seconds compared with 4.881335 seconds, which is 1.1140 times faster or a 10.24 percent improvement. V1 also had exact agreement in the recorded 100-step reference test. The combined version was not selected: it was slower and its reordered floating-point operations accumulated a 7.775 times 10 to the minus 12 position difference, exceeding the deliberately strict 10 to the minus 12 test threshold."

### Result to emphasize

`10.24%` is a measured software improvement. It is not a hardware result.

### Likely instructor questions

**Does the combined correctness failure mean the physics is completely wrong?**

No. The final energy difference was only `3.886e-15`, but the maximum position difference exceeded the configured strict threshold. The honest scripted verdict is still FAIL, and the combined version was not selected.

**Why use a short correctness test for V1?**

It is a fast gate for preserving equations and update order before expensive benchmark runs. A stronger future test would also run V1 for the full 20,000 steps and define justified absolute and relative tolerances.

## Slide 7: Hardware Motivation

### What the slide should show

- Left: remaining V1 hotspots: interpreter, boxed floats, multiplication, power.
- Center: repeated pair formula.
- Right: a hardware datapath icon labeled "one pair result per cycle after fill, simulation only."
- A red boundary label: "Separate RTL implementation, not connected to Python."

### What I should say

"After scalarization removes most list reads, interpreter and numeric-operation costs remain. The body-pair kernel has a fixed sequence of squares, square root, reciprocal, mass scaling, and six velocity-delta products. That regular arithmetic is a reasonable hardware target. I implemented that target separately in SystemVerilog and verified its function, but I did not replace the Python function with hardware. Therefore, there is no measured hardware application speedup."

### Result to emphasize

Hardware motivation is supported by repetition and profiling, while actual acceleration remains a proposal until integration and end-to-end measurement exist.

### Likely instructor questions

**Can you derive hardware speedup from the perf percentages?**

Not reliably. Symbol percentages overlap software runtime services and do not isolate the exact offloadable fraction. Amdahl estimates require explicit assumptions, while a real speedup claim requires an integrated measurement.

**Why accelerate one pair instead of the complete timestep?**

A pair core is reusable, streamable, and straightforward to verify. A full-timestep engine could retain all body state and reduce transfers, but it requires more storage, scheduling, accumulation logic, and a larger verification scope.

## Slide 8: Fixed-Point Design

### What the slide should show

A format-propagation diagram:

```text
Q16.16 delta
 -> Q32.32 square and d2 (64 bits)
 -> Q16.16 integer sqrt
 -> Q48.48 denominator (96 bits)
 -> Q16.16 inv_r3
 -> Q48 scale (96 bits)
 -> Q64 signed delta product (129-bit container)
 -> round, shift 48, saturate to Q16.16
```

Include the reciprocal derivation:

$$
denominator_{raw} \approx d^2\sqrt{d^2}\,2^{48}
$$

$$
inv\_r^3_{raw} = \frac{2^{64}}{denominator_{raw}}
$$

### What I should say

"The interface uses signed Q16.16 for deltas and outputs and unsigned Q16.16 for masses and timestep. Squaring produces Q32.32. Multiplying by the Q16.16 square root gives a 96-bit Q48.48 denominator. To obtain a Q16.16 reciprocal cube, the numerator is 2 to the 64. The design keeps wide intermediates, then applies symmetric rounding and signed saturation at the output."

### Result to emphasize

The scaling is derived from raw integer representations. The corrected RTL computes $1/(d^2\sqrt{d^2})$, unlike the original proposal, which effectively computed a scaled reciprocal of $d^2$.

### Likely instructor questions

**Why choose Q16.16?**

It gives a simple 32-bit interface with 16 fractional bits and deterministic integer arithmetic. It is a design trade-off, not proof that every possible Nbody state fits; broader range and error analysis would be needed for a production design.

**How are negative values rounded?**

The final conversion uses symmetric round-to-nearest with ties away from zero, followed by signed saturation. This avoids the positive/negative bias of applying only an unsigned rounding offset.

**What happens at zero distance?**

The reciprocal saturates internally. Because `dx`, `dy`, and `dz` are all zero, every output delta remains zero. This finite policy is explicitly tested.

## Slide 9: Five-Stage RTL Pipeline

### What the slide should show

```text
S1                S2                    S3           S4             S5
square + d2  ->   sqrt + denominator -> inv_r3  ->  two scales -> six deltas
Q32.32             Q48.48               Q16.16       Q48            Q16.16
```

Under the diagram:

- Five clocks from accepted input to output transfer when unstalled.
- One pair transaction per cycle after fill.
- Global stall freezes all payload and valid registers.
- ModelSim: `PASS`, 12 transfers, 0 compile errors, 0 warnings.

### What I should say

"Each stage has a matching valid bit, and every operand is delayed with its transaction. Stage 1 computes squared distance. Stage 2 computes integer square root and the denominator. Stage 3 computes inverse cube. Stage 4 computes separate cross-mass scales. Stage 5 creates both bodies' velocity deltas, rounds, and saturates. Backpressure freezes the whole pipeline, preventing valid/data misalignment."

### Result to emphasize

The measured simulation result is five-clock latency and one transaction per cycle after fill. This is functional RTL simulation, not post-synthesis frequency or wall-clock performance.

### Likely instructor questions

**Why was valid-data alignment important?**

Nonblocking assignments read previous-cycle values. Without stage-specific valid and delayed operands, an output can combine values from different requests while being labeled as the newest request.

**Can the current divider really accept one input every clock after synthesis?**

The RTL describes a combinational divide within a pipeline stage, so simulation permits that initiation interval. Synthesis timing may be poor or fail the target frequency. A production design would likely use pipelined vendor IP or an iterative reciprocal design, which may change latency or throughput.

## Slide 10: Proposed HW/SW Interface

### What the slide should show

```text
Python Nbody -> driver/API -> MMIO/FIFO/DMA -> nbody_accel
             <- six velocity deltas per pair <-
```

Input record, 24 bytes:

```text
dx, dy, dz, mass_i, mass_j, dt
```

Output record, 24 bytes:

```text
dvix, dviy, dviz, dvjx, dvjy, dvjz
```

Show the fixed 10-pair order and `PAIR_COUNT = 10`.

### What I should say

"In a real system, a native API would convert the current pair data to Q16.16 and construct 10 input records. DMA would stream those records through the accelerator's ready/valid interface. The accelerator returns both bodies' three-axis velocity deltas for every pair. Software then converts and accumulates all 10 outputs in the original pair order before updating positions. Batching is necessary because one Python-to-MMIO call per pair would likely erase the arithmetic benefit."

### Result to emphasize

This is a proposed architecture. No driver, DMA wrapper, MMIO block, native extension, or Python call path was implemented.

### Likely instructor questions

**Why return velocity deltas instead of updated velocities?**

Multiple pairs contribute to each body during a timestep. Returning pair-local deltas keeps the hardware core stateless and lets software preserve the original accumulation order.

**Why is no pair ID included?**

The input and output streams preserve order, so each record slot implicitly identifies one of the fixed 10 pairs. A more general asynchronous or multi-core architecture could add transaction and pair IDs.

## Slide 11: Performance, Area, and Power Trade-offs

### What the slide should show

A three-column trade-off table:

| Choice | Benefit | Cost |
|---|---|---|
| Full spatial pipeline | One result/cycle after fill | Many wide arithmetic units |
| Shared iterative units | Lower area and switching | Lower throughput, more control |
| Q16.16 | Compact deterministic interface | Limited range and precision |
| Five stages | Higher potential throughput | Registers and clock power |
| Global stall | Simple correct control | Entire pipeline stops on backpressure |

Add: "No synthesis numbers available."

### What I should say

"The current RTL favors clarity and throughput in simulation. It expresses 14 logical multiplication operations, including six wide final products, plus a combinational integer square root and variable divider. That count is not an FPGA DSP count because synthesis can split or remap operations. Sharing units could reduce area and power, but it would sacrifice one-pair-per-cycle throughput. Since I did not synthesize the design, I do not report LUTs, DSPs, frequency, watts, or energy."

### Result to emphasize

The dominant implementation risk is the wide divider and combinational square-root path, not ready/valid control.

### Likely instructor questions

**How many DSP blocks does the design use?**

Unknown. The RTL has 14 logical multiplication operations, but physical DSP mapping depends on operand widths, target device, synthesis settings, and whether the tool decomposes or shares operators.

**How would you reduce power?**

Options include operand isolation or clock gating during invalid cycles, iterative shared arithmetic, a lower-cost reciprocal approximation, narrower validated formats, and avoiding unnecessary switching under backpressure.

## Slide 12: Limitations and Honest Boundaries

### What the slide should show

Two columns:

**Completed**

- Python variants executed and benchmarked.
- Original and V1 profiled.
- V1 measured at 10.24% improvement.
- RTL functionally verified in ModelSim.
- Reset, ordering, backpressure, numerical tolerance, zero distance, and saturation tested.

**Not completed**

- FPGA/ASIC synthesis.
- Timing closure and maximum frequency.
- Area or power analysis.
- MMIO/DMA wrapper and Python driver.
- End-to-end hardware runtime.
- Measured hardware speedup.

### What I should say

"The measured result is the software speedup. The hardware result is functional simulation of a separate accelerator. I verified that the core computes ordered fixed-point velocity deltas and obeys backpressure, but I did not synthesize it or connect it to Python. Therefore, any Amdahl-law scenarios are labeled estimates and are not presented as project measurements."

### Result to emphasize

Being explicit about evidence boundaries strengthens the result: `10.24%` is measured software performance; `five clocks` and `one per cycle` are simulation behavior; end-to-end hardware acceleration is unmeasured.

### Likely instructor questions

**What is the most important missing experiment?**

Implement the wrapper and driver, synthesize on a specified target, and measure complete Nbody runtime including conversion, transfer, synchronization, and software accumulation.

**What would invalidate the expected hardware benefit?**

If conversion and transfer overhead exceed the saved Python arithmetic time, or if synthesis forces a low clock rate or multi-cycle initiation interval, end-to-end performance could show little or no gain.

## Slide 13: Conclusion

### What the slide should show

Three final takeaways:

1. **Profile-driven software result:** V1 reduced list-read overhead and measured `1.1140x` speedup.
2. **Correct hardware kernel:** five-stage fixed-point pair accelerator passed comprehensive simulation.
3. **Next proof point:** integrate, synthesize, and measure end to end.

Use the central result again:

```text
Measured software: 4.881335 s -> 4.381726 s, 10.24% faster
Verified RTL simulation: PASS, 5-cycle latency, 1 pair/cycle after fill
Measured hardware application speedup: not available
```

### What I should say

"The main software contribution is a measured 10.24 percent improvement from scalarizing repeated list accesses, supported by perf and flamegraph evidence. The main hardware contribution is a corrected five-stage Q16.16 implementation of the same pair kernel, including true inverse cube, both body updates, valid-data alignment, rounding, saturation, and backpressure. It passed comprehensive simulation. The next step is not to claim a theoretical win; it is to build the interface, synthesize for a target, and measure the complete application."

### Result to emphasize

The project demonstrates a complete optimization and verification argument without confusing measured software performance with proposed hardware acceleration.

### Likely instructor questions

**What single lesson did the project demonstrate?**

Measure each optimization independently. V1 helped, later transformations did not compose, and hardware capability cannot be converted into an application speedup claim without integration.

**What would you do next?**

First synthesize and characterize the core. Then implement a batched DMA wrapper and native Python API, validate fixed-point application-level error across full runs, and measure end-to-end runtime against the same baseline.

## Final Technical Question Bank

### 1. What exactly was accelerated in software?

Repeated Python list reads in the velocity and position update paths were replaced with local scalar variables. Arithmetic was performed on locals and grouped writes returned values to the lists.

### 2. What is the final measured software speedup?

The staged comparison measured `4.881335 s` for the original and `4.381726 s` for V1, giving `1.1140x` speedup or `10.24%` improvement.

### 3. Why is V1 called the best version when a combined optimized file exists?

"Optimized" describes the combined experiment, not its measured ranking. The combined version took `5.463925 s`, which was `11.94%` slower than the original. V1 was selected because it had the lowest measured time.

### 4. Which profile evidence most directly validates V1?

`list_subscript.lto_priv.0` fell from `1.89%` to `0.01%`, and `PyObject_GetItem` fell from `1.85%` to `0.02%`. Those are the read paths scalarization was intended to remove.

### 5. Why do some optimized profile percentages increase?

Perf percentages are relative to each run's total samples. When list-read work disappears and total runtime falls, remaining functions can occupy a larger percentage without taking more absolute time.

### 6. Why are there exactly 10 pair interactions?

Five bodies have $5\times4/2=10$ unique unordered pairs. Each pair evaluation updates both bodies.

### 7. What equation does the hardware implement?

It computes $d^2=dx^2+dy^2+dz^2$, then $inv\_r^3=1/(d^2\sqrt{d^2})$, and returns $-\Delta r\,dt\,m_j\,inv\_r^3$ for body i and $+\Delta r\,dt\,m_i\,inv\_r^3$ for body j.

### 8. What was wrong with computing only `1/d2`?

Since `d2` is $r^2$, `1/d2` is $1/r^2$. The vector update multiplies displacement by $1/r^3$, so the missing square-root factor changes the physics.

### 9. Why does body i use `mass_j`?

Acceleration of body i due to body j is proportional to body j's mass. The common gravitational constant is absorbed by the benchmark's units.

### 10. Why is the reciprocal numerator $2^{64}$?

The denominator raw value represents $d^2\sqrt{d^2}$ with 48 fractional bits. A Q16.16 reciprocal output needs another 16 fractional bits, so the integer numerator scale is $2^{48+16}=2^{64}$.

### 11. What are the pipeline stages?

Stage 1 computes squared distance, stage 2 computes square root and denominator, stage 3 computes inverse cube, stage 4 computes the two mass/time scales, and stage 5 computes, rounds, and saturates six signed velocity deltas.

### 12. How does backpressure work?

If the final output is valid and `out_ready` is low, the global pipeline enable is low. Every valid and payload register holds its value until the output can transfer.

### 13. What RTL behavior was actually measured?

ModelSim measured functional behavior under the testbench: five clocks from input acceptance to output transfer when unstalled, one transaction per cycle after fill, stable data under backpressure, and 12 correctly ordered transfers.

### 14. Was the accelerator synthesized?

No. There are no resource, timing, frequency, power, or energy results. The current claims are limited to synthesizable RTL structure and functional simulation.

### 15. Was Python connected to the accelerator?

No. The driver/API, MMIO or DMA wrapper, conversion path, and physical hardware connection are proposed only.

### 16. Why is DMA batching necessary?

The arithmetic payload per pair is small. Repeated Python calls and MMIO transactions could dominate it. A batch of all 10 pair records amortizes setup and synchronization overhead.

### 17. What data crosses the proposed interface?

Each input record contains `dx`, `dy`, `dz`, `mass_i`, `mass_j`, and `dt`. Each output contains three velocity deltas for body i and three for body j. Every field is 32-bit Q16.16.

### 18. How is numerical error handled?

The datapath retains wide intermediates, uses integer square-root and reciprocal quantization, then applies symmetric rounding and signed saturation. The testbench uses exact checks for representable vectors and explicit 3- or 16-LSB tolerances for non-axis-aligned vectors.

### 19. Why not update body velocities directly in hardware?

Each body receives contributions from four pair interactions. Returning pair-local deltas keeps the core stateless and streamable. Software can merge them in the original order; a stateful hardware accumulator is a possible future extension.

### 20. What is the main timing risk in the RTL?

The wide variable divider and fixed-iteration combinational square root are likely critical paths. Simulation does not prove that they meet a useful clock frequency after synthesis.

### 21. How would you improve the RTL for a real FPGA?

Use characterized pipelined square-root and divider IP, or use reciprocal approximation with refinement; choose widths from a formal range/error study; synthesize against a specific clock; and add an AXI-stream or equivalent DMA wrapper.

### 22. Why can you not claim the Amdahl estimates as results?

Their offload fraction, kernel acceleration, and interface overhead are assumed rather than measured. They illustrate sensitivity but do not describe an implemented system.

### 23. How would you measure end-to-end hardware speedup correctly?

Time the same full benchmark workload including conversion, DMA setup, transfer, waiting, result conversion, ordered accumulation, and remaining Python work. Compare multiple statistically controlled runs against the same software baseline.

### 24. What does the combined correctness failure teach?

Floating-point reordering accumulates small state differences over long simulations. Correctness criteria should include justified numerical tolerances, not only mathematical equivalence of transformed expressions.

### 25. What are the three strongest defensible claims?

First, V1 measured `10.24%` faster in the staged run. Second, perf confirms that V1 nearly removes list-read paths. Third, the separate corrected RTL passed its comprehensive functional simulation with five-cycle unstalled latency and one-result-per-cycle simulated throughput.
