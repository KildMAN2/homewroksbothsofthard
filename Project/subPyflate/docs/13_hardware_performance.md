# Pyflate — Hardware Performance ESTIMATES

**All numbers here are ESTIMATES unless explicitly labeled MEASURED.**

Measured software results live in `docs/06_final_software.md`.
Simulated RTL results live in `hw/results/SIMULATION_RESULTS.txt`.
Physical hardware speedup has NOT been measured — no synthesis,
place-and-route, FPGA deployment, or hardware-in-the-loop benchmarking has
been performed. That work is listed as remaining in
`docs/06_final_software.md` and in the report conclusion.

## 1. Software Baseline (measured)

Populated after the VM run — see `docs/06_final_software.md` for the
official original/final numbers. Fill in the placeholders below.

- Original wall-clock mean: `TBD` s (from `results/original_official.txt`).
- Final wall-clock mean: `TBD` s (from `results/final_official.txt`).
- Improvement: `TBD` %.

## 2. Accelerated Fraction (measured)

The fraction of runtime spent inside the accelerator's target
(`HuffmanTable.find_next_symbol` + `RBitfield.readbits/snoopbits` +
`RBitfield.needbits/_more`) is derived from
`profiling/perf_report_baseline.txt`. Fill in from that report:

- `P` = fraction of BASELINE runtime replaceable by the accelerator. TBD.

## 3. Accelerator Speed Assumption (ESTIMATE)

Assume the pipelined v2 accelerator processes 1 symbol per clock at 200
MHz. Software Python-level `HuffmanTable.find_next_symbol` averages roughly
`k` interpreter steps per symbol, where `k` is O(#codes / 2). Absolute
per-symbol time is measured indirectly by the perf report's self time on
that Python frame.

For Amdahl bounds we use `S ∈ {5, 10, 20}` (i.e. the accelerator does the
per-symbol work 5-20× faster than pure Python). All ESTIMATES.

## 4. Amdahl's Law

```
Speedup(S, P) = 1 / ((1 - P) + P / S)
```

Populate the table once `P` is known. Placeholder using `P` = 0.4 (a
typical Huffman-heavy share):

| `S` | Speedup | Improvement |
|---:|---:|---:|
| 5  | 1 / (0.6 + 0.4/5)  = **1.47×** | 32.0 % |
| 10 | 1 / (0.6 + 0.4/10) = **1.56×** | 36.0 % |
| 20 | 1 / (0.6 + 0.4/20) = **1.61×** | 38.0 % |

For any other measured `P`, recompute with the formula above. Every value
in the table is `ESTIMATE`.

## 5. Communication Overhead (ESTIMATE)

Per bzip2 block:
- LUT upload: `2^MAX_BITS` writes at 1/cycle = up to 32K cycles = 160 µs
  at 200 MHz. Amortized over the block's decoded symbols (~10^6).
- Byte-in / symbol-out: bounded by the AXI4-Stream bandwidth, which is
  much higher than the decoder throughput. Not a bottleneck.
- Total overhead per block: a few percent of block decode time.

## 6. Expected System-Level Speedup (ESTIMATE)

= Amdahl speedup − communication overhead − CPU-side bzip2 post-processing
(BWT, MTF, RLE) which is NOT accelerated in v1.

## 7. Latency (ESTIMATE)

- Session startup: ~5 cycles + LUT upload time (bounded by 32K cycles per
  group, ~160 µs at 200 MHz).
- Steady-state per symbol: 3 cycles (v1) or 1 cycle (proposed v2).

## 8. Throughput (ESTIMATE)

- v1 (implemented): ~66 M symbols/sec at 200 MHz.
- v2 (proposed pipelined): ~200 M symbols/sec at 200 MHz.

Pyflate's dominant workload emits ~10^6 symbols per block; v1 processes a
block's Huffman phase in ~15 ms, v2 in ~5 ms — both ESTIMATES.

## 9. Area Considerations (ESTIMATE)

- 1 LUT BRAM × 32 KiB..84 KiB depending on `MAX_BITS`.
- ~50 flops for the `bit_shifter` buffer.
- ~50 flops + a few comparators + a 3-state FSM for `huffman_decoder`.
- No multipliers, no floating-point.

Compared to the raytrace intersection accelerator (Q16.16 sphere/plane
math with a 32-cycle sqrt), this design is much smaller in logic and much
larger in BRAM — a reasonable different-shape complement.

## 10. Power Considerations (ESTIMATE)

Static: BRAM standby power dominates when idle. Dynamic: the FSM toggles
only a handful of flops per cycle; the LUT BRAM is read exactly once per
symbol. Order-of-magnitude tens of mW at 200 MHz on a mid-range FPGA
(ESTIMATE, no measurement).

## 11. Bottlenecks (ESTIMATE)

- v1: the 3-cycle FSM. Removing the LUT read-wait stage (registering
  `snoop` directly on the LUT read port) removes S_WAIT and drops per-symbol
  cost to 2 cycles; a second pipeline register drops it to 1.
- Communication with Python: today Python calls into a C extension per
  block; the driver call overhead may dominate for tiny blocks.

## 12. Limitations (explicit)

Not measured:
- Synthesis timing at any clock.
- Area or power on real silicon / any FPGA.
- End-to-end wall-clock speedup on the real pyflate workload with the
  accelerator in the loop.
- Interrupt latency.
- DMA throughput.

## 13. Explicit Evidence Boundary

- MEASURED SOFTWARE: `docs/06_final_software.md`.
- SIMULATED RTL: `hw/results/SIMULATION_RESULTS.txt`.
- ESTIMATED HARDWARE: this document.
- PROPOSED SYSTEM INTEGRATION: `docs/12_hw_sw_interface.md`.

No claim is made of measured FPGA speedup, measured ASIC area, measured
operating frequency, or measured hardware power. Estimates use standard
Amdahl's Law with clearly-labeled assumptions.
