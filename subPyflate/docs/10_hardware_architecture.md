# Pyflate — Hardware Architecture

## 1. Accelerator Purpose

Decode a stream of canonical Huffman codes from a compressed byte stream
into a stream of (symbol, code_length) pairs, matching bzip2's MSB-first
semantics (`RBitfield` in the pyflate software).

## 2. Functional Specification

```
FOR each requested symbol:
    1. Snoop the top MAX_BITS bits of the rolling bit buffer.
    2. Index the precomputed canonical Huffman LUT with those bits.
    3. Emit (symbol, code_bits) from the LUT entry.
    4. Consume `code_bits` bits from the buffer.
    5. If needed, refill the buffer by accepting one byte from the input
       stream (backpressure = `byte_ready`).
STOP after `max_symbols` symbols have been emitted, OR when the LUT
returns `code_bits == 0` (unknown code → error latched, driver falls
back to software decode for that symbol).
```

## 3. Inputs

| Name | Width | Meaning |
|---|---:|---|
| `clk` | 1 | Positive-edge system clock. Estimated target 200 MHz on a mid-range FPGA (ESTIMATE). |
| `rst_n` | 1 | Active-low synchronous-reset gate. |
| `table_wr_en` | 1 | Assert while writing one LUT entry per cycle. |
| `table_wr_addr` | `MAX_BITS` | Index of the LUT entry to write. |
| `table_wr_symbol` | `SYMBOL_WIDTH` (16) | Symbol value stored at that index. |
| `table_wr_bits` | 5 | Code length. `0` marks an unused index. |
| `start` | 1 | Kick off a decode session. |
| `max_symbols` | `COUNTER_W` (32) | Number of symbols this session should emit. |
| `byte_valid` | 1 | Driver is presenting a fresh byte this cycle. |
| `byte_data` | 8 | Byte value. Interpreted MSB-first (same as `RBitfield`). |

## 4. Outputs

| Name | Width | Meaning |
|---|---:|---|
| `byte_ready` | 1 | Bit shifter can accept a byte this cycle. |
| `symbol_valid` | 1 | Pulses for one cycle when a symbol is emitted. |
| `symbol_out` | `SYMBOL_WIDTH` (16) | Decoded symbol. |
| `symbol_bits` | 5 | Code length that produced it. |
| `busy` | 1 | 1 while a session is active. |
| `done` | 1 | 1-cycle pulse when the last symbol was emitted normally. |
| `error` | 1 | 1-cycle pulse when the LUT returned `code_bits == 0`. |

## 5. Datapath

Three RTL modules:

- `huff_lut` (`hw/rtl/huff_lut.sv`) — synchronous BRAM-shaped storage. One
  write port (CPU) and one read port (decoder). Depth = `1 << MAX_BITS`,
  each entry = `{code_bits[4:0], symbol[15:0]}`.
- `bit_shifter` (`hw/rtl/bit_shifter.sv`) — rolling MSB-first bit buffer
  matching `RBitfield`. Exposes `snoop`/`consume`/`byte_valid`/`byte_ready`.
- `huffman_decoder` (`hw/rtl/huffman_decoder.sv`) — top FSM that ties LUT
  and shifter together plus counts down `symbols_left`.

Combinational signal flow:
```
byte_valid,byte_data ──▶ bit_shifter ──snoop──▶ huff_lut ──▶ (symbol,bits)
                                    ▲                             │
                                    │                             ▼
                                    └──── consume (=code_bits) ◀──┘
```

## 6. Control (FSM)

`huffman_decoder` FSM states:

```
S_IDLE  ──start──▶ S_ISSUE
S_ISSUE ──snoop_ready──▶ S_WAIT   (asserts lut_rd_en)
S_WAIT  ──lut_rd_valid & bits!=0──▶ S_CONSUME
        ──lut_rd_valid & bits==0──▶ S_IDLE  (error latched)
S_CONSUME ──always──▶ S_ISSUE     (emits symbol, consumes bits)
                       or ▶ S_IDLE  (last symbol → done)
```

Throughput of the current (first) implementation is **1 symbol every 3
clocks** worst-case (ISSUE + WAIT + CONSUME). Deeper pipelining (single
cycle per symbol) is described as future work in
`docs/13_hardware_performance.md`.

## 7. Pipeline

The current design is intentionally single-shot per symbol, not pipelined.
A future v2 would:
- issue back-to-back reads without waiting for `lut_rd_valid` (register the
  buffer's post-consume snoop),
- move `bs_consume` update into a separate write-back stage,
achieving one symbol per cycle at the cost of a two-stage register slice.

## 8. Parallelism

For bzip2's per-block 6-group table set, six independent `huffman_decoder`
instances (each with its own LUT) could decode different groups in
parallel. Not implemented in this v1.

## 9. Registers and Storage

- LUT: `mem [0 : (1<<MAX_BITS)-1]`, entry width `SYMBOL_WIDTH +
  CODE_BITS_W = 21` bits → padded to 32 bits for BRAM friendliness.
  For MAX_BITS=15 total ~84 KiB.
- Bit buffer: `BUF_W` = 32 bits.
- Symbol counter: `COUNTER_W` = 32 bits.

## 10. Memory Interface

- LUT write port used once per Huffman table build. Sustained BW: 32
  bits × ~2^15 addrs = 128 KB per group, at 1 word/cycle = 32 KB/s at very
  low duty cycle. Trivial.
- Byte stream input: 8 bits / cycle peak. At 200 MHz that is 200 MB/s peak
  bandwidth toward the accelerator (again ESTIMATE), well within an
  AXI4-Lite / AXI4-Stream 32-bit / 200 MHz interface (which sustains 6.4
  Gb/s).

## 11. Latency

- Table load: 1 cycle/entry (one write port). MAX_BITS=15 → 32768 cycles =
  164 µs at 200 MHz (ESTIMATE) per group.
- First symbol after start: 3 cycles (ISSUE + WAIT + CONSUME) + shifter
  fill (≥ 2 byte pushes for MAX_BITS = 15 → 2 cycles), so about 5-8 cycles.
- Subsequent symbols: 3 cycles per symbol, minus any byte refill overlap.

Numbers above are `ESTIMATE`. They assume the design synthesizes at 200 MHz
without pipeline breaks; no place-and-route has been performed.

## 12. Throughput

Current v1: 1 symbol / 3 clocks = ~66 M symbols/sec at 200 MHz (ESTIMATE).
Pipelined v2 (proposed): 1 symbol / 1 clock = ~200 M symbols/sec at 200 MHz
(ESTIMATE).

For the pyflate workload, bzip2 blocks emit up to ~2^20 symbols per block.
The v1 pipeline decodes that in ~16 ms; the v2 pipeline in ~5 ms — both
figures being ESTIMATES.

## 13. Clock Assumptions

Target 200 MHz on a Xilinx / Intel mid-range FPGA. Not synthesized, not
measured. Numbers above are ESTIMATES anchored to what a similar
BRAM-based Huffman core has been reported to achieve.

## 14. Block Diagram

```
                       ┌───────────────────────────────────────┐
                       │           huffman_decoder             │
CPU ─── LUT write ────▶│                                       │
CPU ─── start ────────▶│  ┌────────┐   snoop    ┌────────┐    │
CPU ─── max_symbols ──▶│  │  bit   │──────────▶│  huff  │    │──▶ symbol_out
CPU ─── byte_valid ───▶│  │shifter │           │  lut   │    │──▶ symbol_bits
CPU ─── byte_data ────▶│  │ (RB)   │◀──consume─│ (BRAM) │    │──▶ symbol_valid
CPU ◀── byte_ready ────│  └───┬────┘           └────┬───┘    │──▶ done
                       │      │                     │        │──▶ error
                       │      │  ┌──────────┐       │        │
                       │      └─▶│  FSM     │◀──────┘        │
                       │         │ S_ISSUE  │                │
                       │         │ S_WAIT   │                │
                       │         │ S_CONSUME│                │
                       │         └──────────┘                │
                       └───────────────────────────────────────┘
```

## 15. Hardware/Software Boundary

Software (Python + a thin driver) is responsible for:
- Building the canonical Huffman table (already done in software today for
  `HuffmanTable.populate_huffman_symbols`).
- Uploading the table via the LUT write port.
- Feeding compressed bytes from the input file.
- Consuming decoded symbols and completing the bzip2 pipeline (MTF, BWT
  inverse, RLE decode).

Hardware handles only the per-symbol Huffman lookup + bit management.

## 16. Trade-offs

- **Area** ↑ vs pure SW: one BRAM (~84 KiB) per active Huffman group.
- **Power** ~ constant during decode; static leakage dominated by BRAM
  standby power. No numbers claimed.
- **Precision**: exact. No fixed-point rounding — this is an integer / bit
  operation.
- **Control complexity**: low. Three-state FSM.
- **Communication overhead**: byte-in + symbol-out at ~8 bits + 21 bits
  respectively per symbol. On an AXI-Lite link at 200 MHz that overhead is
  well below the decode rate.
