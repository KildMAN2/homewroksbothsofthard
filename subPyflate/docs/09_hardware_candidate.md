# Pyflate — Hardware Acceleration Candidate

## 1. Motivation

`docs/04_bottleneck_analysis.md` identifies `HuffmanTable.find_next_symbol`
as the profiled hotspot of `decode_huffman_block`. In the software attempt
1, the same operation was rewritten as an O(1) lookup by table indexing.
That change (a) validates the hotspot and (b) makes the natural hardware
kernel obvious: **implement the same canonical Huffman lookup in a small
BRAM-backed accelerator** and let the CPU stream bytes in / decoded symbols
out.

Hardware-only benefits vs the software LUT:
- Per-symbol overhead drops from ~1 dict-index + arithmetic in Python (still
  several nanoseconds each) to a fixed 2-3 clock cycles at, e.g., 200 MHz.
- The accelerator can be pipelined so throughput reaches one symbol per
  cycle. In pure Python this is impossible.
- The bit-shifter avoids Python's arbitrary-precision integer handling for
  the rolling buffer entirely.

## 2. Candidates Considered

| # | Candidate | Profiling evidence | Parallelism | Memory cost | HW complexity | Expected benefit |
|---|---|---|---|---|---|---|
| A | **Canonical Huffman LUT decoder** (this proposal) | Direct hotspot in `find_next_symbol`. | Deep pipelining possible (1 sym/cycle). | 1 LUT × ~84 KiB (MAX_BITS=15). | Low: small BRAM + FSM + barrel shift. | HIGH — cuts the dominant per-symbol cost. |
| B | BWT inverse transform | Secondary hotspot in `bwt_transform` / `bwt_reverse`. | Not naturally parallel (pointer chase). | Full BWT block in local RAM (~900k bytes/block). | Medium-high: needs full block RAM per group. | Medium — smaller share of runtime. |
| C | Move-to-front unit | Called every symbol; already fixed in SW attempt 2. | Trivial parallelism. | Just the favourites list. | Low. | Small — SW attempt 2 already gets most of this. |
| D | Byte-level RLE decoder | End-of-block loop in `decode_huffman_block`. | Trivial (streaming). | None. | Trivial. | Small. |
| E | CRC-32 checker | Not on pyflate's timed path (bzip2 uses a different CRC and it's not verified per block). | N/A | N/A | N/A | N/A |

## 3. Selection

**Candidate A — Canonical Huffman LUT decoder** — selected.

Reasons:
- Matches the profiled hotspot directly.
- Matches a well-established real-world hardware kernel (every commercial
  DEFLATE / bzip2 hardware decompressor implements exactly this piece).
- Datapath is simple (small BRAM + barrel shifter + FSM), so the design
  fits in a first-project scope with a full self-checking testbench.
- Amdahl analysis (in `docs/13_hardware_performance.md`) shows this is
  where the acceleratable fraction actually lives.

## 4. Interface Sketch (elaborated in docs/10)

- **Inputs**: byte stream (compressed source), Huffman LUT contents, start
  pulse with `max_symbols`.
- **Outputs**: symbol stream with per-symbol code length, done pulse,
  error latch for unknown codes.
- **Control**: fits an AXI4-Lite / MMIO register bank in the future
  integration (see `docs/12_hw_sw_interface.md`).

## 5. Amdahl Sanity Check (moved to docs/13)

The measured fraction of runtime spent inside `find_next_symbol` +
`Bitfield.readbits/snoopbits` should be filled from
`profiling/perf_report_baseline.txt`. `docs/13_hardware_performance.md`
uses that measured fraction with different `S` (hardware speedup)
assumptions to bracket the expected system-level improvement.

## 6. Explicit Non-Goals

- No synthesis, place-and-route, or physical timing closure.
- No real driver / DMA / MMIO integration — those are documented as
  PROPOSED in `docs/12_hw_sw_interface.md`.
- No proof of hardware speedup on the real workload — hardware performance
  numbers in `docs/13_hardware_performance.md` are ESTIMATES with the
  assumptions spelled out.
