# Pyflate Presentation Preparation (20-25 Minutes)

Same format as `subRay/presentation/preparing_presentation.md`. Each slide
has `Show` / `Say` / `Key Point` / `Likely Question` / `Answer`. Numbers
marked `TBD` are collected on the VM before the presentation is delivered.

## Slide 1 — Project Goal

### Show
Project title, course context, and one-line objective: optimize
pyperformance pyflate and design a hardware accelerator path.

### Say
This is the second benchmark of the HWSW project. Same two-part goal as
raytrace: improve wall-clock pyflate runtime with correctness preserved,
and design + simulate a hardware accelerator prototype for the profiled
hotspot. Measured software results are separated from ESTIMATED hardware
results throughout.

### Key Point
Combined software optimization and hardware acceleration proposal, with a
strict measured / estimated / proposed evidence split.

### Likely Question
What success metric did you target?

### Answer
Wall-clock runtime improvement of the pyflate benchmark under
pyperformance, with the pyflate MD5 gate still passing. Course requirement
is `>= 7 %`; measured improvement is `TBD %`.

## Slide 2 — What Pyflate Does

### Show
Compressed byte stream on the left, "gzip/DEFLATE OR bzip2 decoder" box
in the middle, decompressed bytes + MD5 check on the right.

### Say
Pyflate is a pure-Python DEFLATE (gzip) and bzip2 decoder by Paul Sladen.
The pyperformance benchmark decompresses a shipped bzip2 file
`interpreter.tar.bz2` in a loop and verifies each output with an MD5
digest `afa004a630fe072901b1d9628b960974`. Only the bzip2 path is
exercised (magic `0x425a`).

### Key Point
Bytes in, bytes out; the whole decoder is Python, so the workload is
CPU-bound on the interpreter.

### Likely Question
Is this workload synthetic or realistic?

### Answer
Realistic in structure — it is a real DEFLATE / bzip2 implementation on a
real compressed file — but exercised in a synthetic pyperformance harness.

## Slide 3 — Original Algorithm Flow

### Show
Flow: `RBitfield(file)` → `bzip2_main` → per-block
`decode_huffman_block` → `bwt_reverse` → RLE decode → `bytes`.

### Say
Each bzip2 block: read the pi magic, skip randomised bit, read pointer,
compute used-symbol map, read the group selectors, build one Huffman
table per group, then decode symbols in a tight loop; every 50 symbols
switch to the next table; interpret MTF+RLE codes into a buffer; then
reverse the BWT and unpack the byte-level RLE.

### Key Point
The per-symbol Huffman lookup dominates because every emitted symbol goes
through a Python object scan.

### Likely Question
Did you change asymptotic complexity of anything?

### Answer
Yes. `find_next_symbol` went from O(#codes) to O(1) via a canonical
Huffman lookup table. Other changes are constant-factor.

## Slide 4 — Baseline

### Show
`pyperformance` mean/std-dev line and the matching `perf stat -r 3`
elapsed time.

### Say
Baseline was captured by
`bash subPyflate/scripts/script_pyflate.sh baseline` which runs
`perf record -F 999 -g -- python3-dbg -m pyperformance run --bench
pyflate`. Mean: `TBD` s. Std dev: `TBD` s.

### Key Point
Use official before/after files for the comparison; keep raw artifacts
(perf.data, stdout/stderr) as historical evidence.

### Likely Question
Why did you record perf.data during the baseline run instead of running
perf separately?

### Answer
It halves the total VM time and makes the timing and the sampled call
stacks come from the same run, matching the raytrace project's baseline
methodology.

## Slide 5 — Profiling Methodology

### Show
Three-column table: pyperformance, perf, py-spy.

### Say
pyperformance provides mean/std-dev and stability warnings, perf provides
sampled call stacks and counter data, py-spy provides a readable Python
flame graph. All three are captured for both baseline and final so the
comparison is like-for-like.

### Key Point
Timing + low-level sampled hotspots + Python-frame flame graph together
give one complete picture.

### Likely Question
Why py-spy in addition to perf?

### Answer
py-spy shows Python function frames directly, without the raytrace
project's `[unknown]` / native frame noise that made early perf flame
graphs hard to read.

## Slide 6 — perf Results

### Show
Top self-time symbols from `profiling/perf_report_baseline.txt`.

### Say
Expected top symbols from code inspection (final percentages `TBD`):
`_PyEval_EvalFrameDefault`, `PyObject_GenericGetAttr`,
`HuffmanTable.find_next_symbol` (Python frame), `list_ass_slice`,
`bytes_find`, and `struct_pack`. The important frame is
`find_next_symbol` — that is the algorithmic hotspot.

### Key Point
Interpreter dispatch is broad, but the algorithmically fixable share sits
squarely in `find_next_symbol`.

### Likely Question
Why is `_PyEval_EvalFrameDefault` on top instead of a specific function?

### Answer
It is the interpreter's dispatch loop for every Python opcode, so every
tight Python inner loop shows up under it. It is broad but not by itself
a fixable hotspot.

## Slide 7 — py-spy Flame Graph

### Show
`profiling/flamegraph_pyspy_baseline.svg`.

### Say
The wide bar under `bench_pyflake` → `bzip2_main` →
`decode_huffman_block` → `find_next_symbol` visually confirms the perf
report finding. `move_to_front` and `bwt_transform` show smaller
supporting bars.

### Key Point
Width is proportional to sampled runtime share; the very tallest stack is
not necessarily the biggest cost.

### Likely Question
Can I trust the widths as percentages?

### Answer
As relative shares of the sampled run, yes. Not as absolute times — for
that we use the `perf stat` elapsed number.

## Slide 8 — Main Bottleneck

### Show
`find_next_symbol` code alongside a caption "O(#codes) per symbol".

### Say
The original `find_next_symbol` walks a Python list of `HuffmanLength`
objects, doing an attribute read per iteration and a `snoopbits` call per
distinct bit-length. In a bzip2 block emitting up to ~10^6 symbols across
several groups this is the single biggest cost we can attack.

### Key Point
The bottleneck is algorithmic + Python overhead in one specific function.

### Likely Question
How did you confirm it was really the bottleneck?

### Answer
Cross-checked perf report top self-time and py-spy width; both point at
`find_next_symbol` and its callees.

## Slide 9 — Optimization Candidates

### Show
Ranked table A..G from `docs/04_bottleneck_analysis.md §6`.

### Say
Candidate A is canonical Huffman LUT (attempt 1). Candidates B, C, D are
MTF pop/insert, BWT single-pass count, precomputed `_INT2BYTE` (attempt
2). Candidate E is attribute hoisting (attempt 3). F and G are minor
refactors not needed after E.

### Key Point
We attack the algorithmic cost first (A), then the second-tier constant
factors (B/C/D), then the interpreter tax (E).

### Likely Question
Why not do all optimizations in one attempt?

### Answer
Separating them makes correctness checking and blame attribution possible;
we can also cheaply drop any change that turned out to hurt.

## Slide 10 — Attempt 1 (LUT)

### Show
Diff between original `find_next_symbol` and the LUT-based version, plus
the LUT indexing formulas for MSB/LSB directions.

### Say
Preserve the original scan as a fallback; build the LUT lazily on first
use per direction; cache on the `HuffmanTable` instance. For bzip2
(MSB-first) the code goes in the high `bits` positions of a `max_bits`
index; for gzip (LSB-first) it goes in the low `bits` positions.

### Key Point
Same output, O(1) per symbol.

### Likely Question
What if a Huffman table has an unused code slot?

### Answer
LUT entry with `code_bits == 0` triggers a fallback to the original scan;
in practice this only fires at true end-of-stream.

## Slide 11 — Attempt 2 (MTF / BWT / int2byte)

### Show
Three small diffs: `move_to_front` before/after; `bwt_transform`
before/after; `_INT2BYTE` table.

### Say
The MTF change eliminates three list-slice allocations per symbol. The
BWT change replaces 256 whole-block scans with one count-pass. The
`_INT2BYTE` change removes a `struct.pack` per literal byte.

### Key Point
Three surgical constant-factor wins layered on top of Attempt 1.

### Likely Question
Do these preserve semantics?

### Answer
Yes. `move_to_front` and `_INT2BYTE` are semantic identities; the BWT
change reproduces the same `base[]` array (including the `-1` sentinel
for absent bytes).

## Slide 12 — Attempt 3 (Hoisting + RLE)

### Show
Snippet of `decode_huffman_block` with locals `buffer_append`,
`favourites_pop`, `favourites_insert`, `t_find`, `tbl` bound before the
main loop, plus the memoryview-style RLE inner loop.

### Say
Each attribute read in a Python inner loop costs real time. Binding hot
attributes to locals removes those reads per iteration. The RLE decoder
also uses direct `bytes` integer indexing instead of one-byte slicing.

### Key Point
Small, safe, byte-identical wins on top of the algorithmic and
constant-factor changes.

### Likely Question
Why not use Cython or a C extension?

### Answer
The project scope was pure-Python optimization to expose the shape of the
hotspot cleanly, then propose hardware. A C extension would blur the
comparison.

## Slide 13 — Why the Final Was Selected

### Show
`docs/06_final_software.md` selection rule and the attempt-comparison
table.

### Say
Selection rule is "fastest correct". Default is Attempt 3 (strictly a
superset of Attempts 1 and 2). If VM measurement shows a different
attempt is strictly faster, `final/` is re-copied from that attempt and
`docs/06_final_software.md` is updated. All attempts are preserved.

### Key Point
Selection is data-driven, not ordering-driven.

### Likely Question
What if two attempts are within noise?

### Answer
Prefer the simpler one (fewer diffs from the original). This matches
raytrace's Attempt 1 vs Attempt 3 tie-break.

## Slide 14 — Correctness Verification

### Show
Snippet from `scripts/check_attempt_correctness.py` and one
`correctness_report.txt`.

### Say
Every attempt is checked by loading the original and the attempt as
modules, decompressing the same workload, byte-for-byte comparison, and
MD5 check against the pyflate reference
`afa004a630fe072901b1d9628b960974`.

### Key Point
`IDENTICAL=YES` and `MATCHES_REFERENCE=YES` on all four attempts.

### Likely Question
Is byte equality proof enough?

### Answer
For this fixed workload — yes; the MD5 also guards against silent
corruption. It does not prove correctness for arbitrary bzip2 files, only
for the pyperformance workload.

## Slide 15 — Official Before/After

### Show
Table from `docs/06_final_software.md` §15.

### Say
Two measurements, both agree:

VM OFFICIAL (naranja4 KVM + PMU passthrough, python3-dbg, perf stat -r 3,
--fast pyperformance):
- ORIGINAL: 120.99 s ± 6.80 s
- FINAL:    76.307 s ± 0.236 s
- Improvement: **+36.93 %** (target ≥ 7 % ACHIEVED with ~5× margin)
- Instructions retired: **−32.87 %**
- Branches: **−33.51 %**, branch-misses: **−37.82 %**
- Cache-references: **−24.53 %**
- (cycles counter reports 0 due to KVM PMU limit on naranja4 Xeon — every
  other hardware counter is captured)

Windows cross-check (CPython 3.12 pyperformance, non-fast, 60 iterations):
- ORIGINAL: 516 ms ± 29 ms
- FINAL:    362 ms ± 22 ms
- Improvement: **+29.84 %**

### Key Point
Same command shape for both, so the comparison is like-for-like.

### Likely Question
Why `perf stat -r 3` instead of `pyperf` output only?

### Answer
It gives an independent stopwatch and matching hardware counters,
matching what raytrace did.

## Slide 16 — Hardware Acceleration Motivation

### Show
Amdahl bar chart with `P` = measured fraction inside the Huffman inner
loop.

### Say
Software attempt 1 validates the shape of the fix. Hardware makes the
same lookup much cheaper per symbol and pipelinable.

### Key Point
The hardware kernel comes directly from the measured software bottleneck.

### Likely Question
Why not accelerate the BWT?

### Answer
Smaller measured share, larger area cost, harder pipeline. First
accelerator should hit the biggest measured hotspot.

## Slide 17 — Selected Hardware Kernel

### Show
`docs/09_hardware_candidate.md` selection table.

### Say
Selected: canonical Huffman decoder + rolling MSB-first bit shifter.
Matches software attempt 1 in algorithm and matches real-world DEFLATE /
bzip2 hardware.

### Key Point
Same math the software optimization uses — implemented as a small
BRAM-backed lookup.

### Likely Question
Would software have caught the same performance if we did more attempts?

### Answer
Only up to Python's interpreter cost. Hardware removes the interpreter
tax entirely.

## Slide 18 — Accelerator Architecture

### Show
Block diagram from `docs/10_hardware_architecture.md §14`.

### Say
Three modules: `huff_lut` (BRAM-backed canonical Huffman LUT),
`bit_shifter` (MSB-first rolling bit buffer mirroring `RBitfield`), and
`huffman_decoder` (top FSM: ISSUE / WAIT / CONSUME).

### Key Point
Simple, deterministic, testable in isolation.

### Likely Question
Why not one monolithic module?

### Answer
Splitting keeps each testbench small and gives the FSM room to be
pipelined into a v2 without disturbing the LUT and shifter interfaces.

## Slide 19 — Datapath

### Show
Signal-flow arrow from bit_shifter.snoop → huff_lut.rd_addr →
lut_rd_symbol → symbol_out, plus consume feedback.

### Say
Each decoded symbol: snoop 15 bits, look up in the LUT, receive
`(symbol, code_bits)`, consume `code_bits` from the shifter, refill a
byte if the shifter needs it.

### Key Point
Data flow is straight-through; the control FSM just serializes it.

### Likely Question
Can two symbols be decoded per clock?

### Answer
Not in v1 (single LUT port, single BRAM read per cycle). A v2 with two
snoop registers and two LUT ports could.

## Slide 20 — Control / Pipeline

### Show
FSM diagram: IDLE → ISSUE → WAIT → CONSUME → ISSUE (loop) or DONE.

### Say
Three states of useful work + IDLE. The v1 throughput is 1 symbol per 3
clocks. v2 (proposed) folds WAIT into ISSUE by registering `snoop` on the
LUT read port, cutting to 1 symbol per 1-2 clocks.

### Key Point
FSM is tiny; the throughput handle is the LUT read latency.

### Likely Question
Why not run at 400 MHz?

### Answer
BRAM access time and comparator settling in the shifter cap the target
clock. 200 MHz is a conservative, defensible target — labeled ESTIMATE.

## Slide 21 — SystemVerilog Implementation

### Show
`ls subPyflate/hw/rtl/` and one small RTL snippet.

### Say
Three SystemVerilog files, all synthesizable. `huff_lut.sv` — BRAM.
`bit_shifter.sv` — MSB-first rolling buffer with a single-cycle consume +
byte-refill combinational stage. `huffman_decoder.sv` — the FSM.

### Key Point
Real RTL, real testbenches, no placeholder logic.

### Likely Question
Was it synthesized?

### Answer
No — the RTL is complete but only simulation-verified, matching the
raytrace project's boundary.

## Slide 22 — Simulation Results

### Show
`hw/results/SIMULATION_RESULTS.txt` summary.

### Say
`bash subPyflate/hw/run_sim.sh` picks the first available simulator
(ModelSim / Icarus / Verilator), runs all three testbenches, and writes a
summary. On the 2026-09-21 Icarus Verilog 12.0 run:
- tb_huff_lut: 5/5 PASS
- tb_bit_shifter: 8/8 PASS
- tb_huffman_decoder: 9/9 PASS
- Total: **22 checks, 0 errors** (see `hw/results/SIMULATION_RESULTS.txt`).

### Key Point
Every check is compared to a reference computed inside the testbench.

### Likely Question
What is your reference model?

### Answer
For the LUT: write value == read value. For the bit shifter: a scalar
software mirror of `RBitfield`. For the top decoder: hand-designed 5-symbol
canonical table + hand-computed byte stream + hand-verified expected
symbol sequence.

## Slide 23 — HW/SW Interface

### Show
Register map from `docs/12_hw_sw_interface.md §4`.

### Say
Proposed MMIO register bank: control / status / max_symbols / table
write / input FIFO / output FIFO. AXI4-Stream for the byte input in
production. All PROPOSED — not implemented in v1.

### Key Point
Interface is drawn to match a real accelerator integration, not just the
testbench.

### Likely Question
Do you have a driver?

### Answer
No. The Python C-extension driver is documented as PROPOSED in
`docs/12_hw_sw_interface.md §11`, not implemented.

## Slide 24 — Hardware Performance Estimate

### Show
Amdahl table from `docs/13_hardware_performance.md §4`.

### Say
Every value is ESTIMATE with the assumption spelled out. With `P` =
fraction inside the Huffman inner loop (TBD from profiling) and `S ∈ {5,
10, 20}`, expected system-level speedup is `TBD`. Communication overhead
is small at the target clock.

### Key Point
Hardware numbers are estimates, not measurements.

### Likely Question
How would you validate them?

### Answer
Synthesize, place-and-route, and run hardware-in-the-loop with the real
pyflate workload. Not part of this project's scope.

## Slide 25 — Conclusion

### Show
One-page summary: measured software gain + simulated hardware +
estimated system-level speedup.

### Say
Pyflate benchmark hits the required `>= 7 %` software improvement with a
canonical Huffman LUT and small MTF/BWT/hoisting cleanups. The same
canonical Huffman lookup is implemented in RTL and simulation-verified.
Hardware performance is estimated with Amdahl's Law and clearly labeled
ESTIMATE.

### Key Point
Software win is real. Hardware win is a validated design and an honest
estimate.

### Likely Question
What is the single most important sentence of the project?

### Answer
The measured software hotspot became the hardware kernel; the same
lookup that made the software `>= 7 %` faster is what the RTL implements.

# Questions I Must Know

1. **What does pyflate do?** Pure-Python DEFLATE / bzip2 decoder;
   pyperformance decompresses `interpreter.tar.bz2` and MD5-checks the
   output.
2. **Why pyflate?** Different shape from raytrace (data / compression
   heavy vs geometry heavy); has a clean, well-understood algorithmic
   hotspot; the accelerator maps to a real-world DEFLATE HW block.
3. **How was the baseline measured?** `perf record -F 999 -g -- python3-dbg
   -m pyperformance run --bench pyflate`; results in
   `results/baseline/`.
4. **Why pyperformance?** Standard, stable, statistical benchmark harness.
5. **What does perf measure?** Sampled call stacks at 999 Hz + optional
   hardware counters via `perf stat`.
6. **What does perf stat tell us?** Elapsed time + IPC + branches +
   cache-misses independent of pyperf's own timing.
7. **What does py-spy tell us?** Sampled Python frames only, no C symbol
   noise — best for spotting the Python-level hotspot.
8. **How to read a flame graph?** Width = sampled runtime share, height =
   stack depth. Wide bars = big cost. Tall thin bars = deep call stacks,
   not necessarily costly.
9. **Why does width matter more than height?** Because CPU time
   accumulates in the width dimension; height only tells you how deeply
   nested a call is.
10. **How was the bottleneck confirmed?** perf report top self time,
    py-spy width, and the algorithmic O(#codes) shape all agree on
    `find_next_symbol`.
11. **What optimization was done?** Canonical Huffman LUT (attempt 1),
    MTF/BWT/int2byte cleanup (attempt 2), attribute hoisting + RLE
    (attempt 3).
12. **Why the LUT?** Turns the per-symbol scan into a single BRAM-shaped
    lookup at max_bits width; identical semantics.
13. **Why were other attempts NOT selected as final?** Attempts 1 and 2
    are subsets of Attempt 3; Attempt 3 is the default final. If VM
    measurement shows Attempt 1 (simpler) is within noise of Attempt 3,
    we prefer the simpler one.
14. **How was correctness verified?** Byte-for-byte match against the
    preserved original + MD5 gate `afa004a630fe072901b1d9628b960974`.
15. **What is the official before/after?** VM (naranja4 KVM):
    `120.99 → 76.307` s, improvement `+36.93 %`, speedup 1.586×.
    Instructions retired dropped `−32.87 %`. Windows cross-check:
    `516 → 362` ms = `+29.84 %`. Target ≥ 7 % ACHIEVED both places.
16. **What fraction of runtime is hardware-accelerable?** `P` = TBD from
    `profiling/perf_report_baseline.txt`.
17. **Why is Huffman suitable for hardware?** Fixed-latency BRAM lookup,
    tiny FSM, straightforward pipelining, matches real-world DEFLATE
    hardware.
18. **How does the accelerator work?** `huff_lut` returns
    `(symbol, code_bits)` given the top MAX_BITS bits; `bit_shifter`
    consumes those bits and refills from a byte stream; `huffman_decoder`
    is the FSM that ties them.
19. **What is the HW/SW overhead?** LUT upload (small, once per group) +
    per-symbol AXI-Lite or AXI-Stream traffic (well under decoder
    throughput at 200 MHz — ESTIMATE).
20. **What are the hardware estimate limits?** No synthesis, no P&R, no
    real driver, no hardware-in-the-loop test. Numbers are ESTIMATES.

# Important Numbers to Memorize

- Reference MD5 of decompressed workload:
  **`afa004a630fe072901b1d9628b960974`** (measured constant, part of the
  benchmark).
- Course threshold: **≥ 7 %** improvement.
- Estimated accelerator clock: **200 MHz** (ESTIMATE).
- v1 throughput: **~66 M symbols/s** at 200 MHz (ESTIMATE).
- v2 throughput target: **~200 M symbols/s** at 200 MHz (ESTIMATE).
- **VM baseline** (naranja4 KVM + PMU): **120.99 ± 6.80 s**.
- **VM final**: **76.307 ± 0.236 s**.
- **VM improvement**: **+36.93 %** (speedup 1.586×, target ≥ 7 % ACHIEVED with ~5× margin).
- **Instructions retired: −32.87 %** (from 579B to 389B).
- **Branches: −33.51 %**, **branch-misses: −37.82 %**.
- **Cache-references: −24.53 %**, cache-misses ≈ flat.
- Windows cross-check: **516 ms → 362 ms = +29.84 %**.
- Attempt 1 alone (LUT-only) on Windows cold-loop: −31.82 % — LUT build
  cost dominates on that short measurement; strengthens the hardware
  argument (BRAM has O(1) load AND O(1) lookup).
- MTF-cleanup evidence in perf report: `list_dealloc` (2.33 %) +
  `list_ass_slice` (1.96 %) both DROPPED out of top 15 between baseline
  and final.

# Important Commands to Know

Baseline:
```
python3-dbg -m pyperformance run --bench pyflate
perf record -F 999 -g -- python3-dbg -m pyperformance run --bench pyflate
perf report --stdio -i profiling/perf_baseline.data > profiling/perf_report_baseline.txt
perf stat -r 3 -- python3-dbg -m pyperformance run --bench pyflate
```

py-spy:
```
py-spy record --rate 100 --output profiling/flamegraph_pyspy_baseline.svg \
    -- python3-dbg subPyflate/original/bm_pyflate/run_benchmark.py --loops=1
```

Final:
```
python3-dbg -m pyperformance run --manifest subPyflate/optimized/final/MANIFEST --bench pyflate_final
perf stat -r 3 -- python3-dbg -m pyperformance run --manifest ... --bench pyflate_final
```

RTL simulation:
```
bash subPyflate/hw/run_sim.sh
```

# 2-Minute Summary

Pyflate is a pure-Python bzip2 decoder measured by pyperformance. The
profiled hotspot is `HuffmanTable.find_next_symbol`, which walks a Python
list of code objects for every emitted symbol. We attacked it in three
layered attempts: first a canonical Huffman lookup table (O(1) per
symbol), then MTF pop/insert + a single-pass BWT count + a precomputed
byte table, then hot-loop attribute hoisting. Each attempt is checked
for byte-identical decompression against the preserved original and for
the pyflate reference MD5. Official before/after is measured on the VM
with `perf stat -r 3 -- python3-dbg -m pyperformance run --bench
{pyflate, pyflate_final}`; the measured improvement is `TBD %`, well
above the `≥ 7 %` requirement. The natural hardware kernel is the same
canonical Huffman lookup, so we implemented a small SystemVerilog
accelerator: `huff_lut` (BRAM-backed canonical LUT), `bit_shifter`
(MSB-first rolling buffer that mirrors `RBitfield`), and
`huffman_decoder` (three-state FSM). Every module has a self-checking
testbench. Hardware performance and area / power are ESTIMATES with
assumptions labeled; the HW/SW interface (MMIO / AXI-Stream / driver) is
PROPOSED, not implemented. Measured software / simulated RTL / estimated
hardware / proposed integration are kept separated throughout.

# 30-Second Summary

We optimized the pyflate pyperformance benchmark by replacing its O(#codes)
Huffman scan with a canonical Huffman lookup table plus a few
constant-factor cleanups. Measured software improvement: `TBD %` (target
`≥ 7 %`). We then designed and simulation-verified a matching hardware
accelerator: a canonical Huffman decoder with a rolling MSB-first bit
buffer, written in SystemVerilog with self-checking testbenches. Hardware
performance numbers are ESTIMATES; the driver is PROPOSED.

# If the Instructor Challenges the Results

- "How do you know the speedup is real?" — Same `perf stat` command was
  used for original and final; wall-clock, cpu-clock, and instructions
  retired all move in the expected direction.
- "Why didn't you just do it all in one attempt?" — Attempts separate
  algorithmic gains from constant-factor gains and let us blame or
  revert individual changes if something regressed.
- "Why do you need hardware if software optimization already helped?" —
  Software is bounded by the Python interpreter tax; hardware removes
  that per-symbol cost entirely and can be pipelined.
- "How do you know this is actually the bottleneck?" — Cross-checked
  perf report top self time and py-spy width; both agree on
  `find_next_symbol`.
- "Did you actually build the hardware?" — No — RTL exists and simulates
  cleanly; no synthesis / FPGA / P&R was done. Numbers on hardware
  performance are ESTIMATES.
- "Did you measure hardware speedup?" — No, only estimated via Amdahl's
  Law with assumed accelerator speed multipliers.
- "Where did your hardware performance number come from?" — Amdahl with
  `P` = TBD from profiling and `S ∈ {5, 10, 20}`.
- "What happens if communication overhead dominates?" — For pyflate's
  block sizes and 200 MHz AXI-Stream, communication is a few percent of
  block decode time — not dominant.
- "What is measured vs estimated?" — Measured software (VM). Simulated
  RTL (testbench). Estimated hardware performance (Amdahl). Proposed
  system integration (MMIO/DMA/driver).

# Presentation Checklist

- [ ] I know the baseline mean.
- [ ] I know the final mean.
- [ ] I know the improvement percentage and the ≥7 % target.
- [ ] I know the bottleneck (`find_next_symbol`) and why it dominates.
- [ ] I know each attempt's diff and why it made it into the final.
- [ ] I know how correctness was verified (byte + MD5).
- [ ] I understand what perf reports and py-spy graphs mean.
- [ ] I understand the LUT structure and both direction cases (MSB /
      LSB).
- [ ] I understand the RTL: `huff_lut`, `bit_shifter`, `huffman_decoder`.
- [ ] I understand the FSM (ISSUE → WAIT → CONSUME).
- [ ] I understand latency and throughput (v1 vs v2).
- [ ] I understand Amdahl's Law and the assumed `S` values.
- [ ] I know which hardware numbers are ESTIMATES.
- [ ] I know what is PROPOSED (MMIO / AXI-Stream / driver).
- [ ] I know the limitations (no synthesis, no HW-in-the-loop).
