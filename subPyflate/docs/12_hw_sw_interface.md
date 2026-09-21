# Pyflate — HW/SW Interface (Proposed)

This document describes how the accelerator would integrate with the CPU
and Python software. The `huffman_decoder` RTL is IMPLEMENTED and
SIMULATED; the register map, DMA, and driver are PROPOSED — not
implemented. This matches the "IMPLEMENTED / SIMULATED / ESTIMATED /
PROPOSED" split used in `subRay/docs/08_hw_sw_interface.md`.

## 1. Software Role

- Load compressed input file into a shared buffer.
- Parse bzip2 headers (still done in Python — cheap and infrequent).
- Build canonical Huffman tables per group (already done today in
  `HuffmanTable.populate_huffman_symbols`).
- Upload each Huffman LUT to the accelerator via the write port.
- Point the accelerator at the current input byte offset.
- Issue `start` with `max_symbols` = the maximum number of symbols the
  hardware should emit before returning (usually one block's worth).
- Collect decoded symbols into a Python bytearray for the rest of the
  bzip2 pipeline (MTF, BWT inverse, RLE decode).

## 2. Accelerator Role

- Present `snoop` bits to its LUT.
- Emit decoded symbols one at a time (or one per cycle in the pipelined
  v2) with associated code length.
- Consume bits from its rolling buffer.
- Raise `done` when `max_symbols` symbols have been emitted or `error`
  when the LUT returns an unused slot.

## 3. Input Data Transfer (PROPOSED)

Two integration options:

- **AXI4-Stream** input: the CPU (or a DMA engine) pushes bytes into the
  accelerator's `byte_valid`/`byte_data`/`byte_ready` handshake port.
  Latency-tolerant.
- **AXI4-Lite MMIO** input register: for low-throughput workloads, the CPU
  writes a byte at a time. Simpler, but limited by CPU bus bandwidth.

For pyflate the stream is small (~1 MB compressed) but the accelerator is
throughput-bound on a small number of hot code paths, so AXI4-Stream is
the natural choice.

## 4. Configuration Registers (PROPOSED)

At MMIO base `BASE`:

| Offset | Name | Access | Description |
|---:|---|---|---|
| `0x00` | `CTRL` | R/W | `[0]` = start pulse, `[1]` = flush. |
| `0x04` | `STATUS` | R | `[0]` = busy, `[1]` = done, `[2]` = error. |
| `0x08` | `MAX_SYMBOLS` | R/W | Session length, `COUNTER_W` = 32 bits. |
| `0x0C` | `TABLE_ADDR` | R/W | LUT write address (during table upload). |
| `0x10` | `TABLE_DATA` | W | LUT write data `{code_bits[4:0], symbol[15:0]}`; a write also asserts `table_wr_en` for one cycle. |
| `0x14` | `INPUT_FIFO` | W | Push a compressed byte (only used if AXI4-Stream not connected). |
| `0x18` | `OUTPUT_FIFO` | R | Pop a decoded symbol (`{code_bits[4:0], symbol[15:0]}`). |

## 5. Start

Software writes `MAX_SYMBOLS`, uploads the LUT (each entry via
`TABLE_ADDR` + `TABLE_DATA`), then writes `CTRL[0] = 1` for one cycle.

## 6. Busy / Status

`STATUS[0] = busy` is polled by software (or converted into an interrupt
in a future integration). `STATUS[1] = done` and `STATUS[2] = error` are
sticky until the next `start`.

## 7. Completion

- Normal: `done` pulses after the `MAX_SYMBOLS`-th symbol is emitted.
  Software drains `OUTPUT_FIFO` until empty.
- Error: `error` pulses. Software reads the current symbol count from a
  status register (not modeled in v1), then falls back to the software
  decoder for the remaining symbols.

## 8. Output Data

Symbol width = 16 bits, code length = 5 bits — total 21 bits per output.
Stored packed in a 32-bit AXI4-Stream word or a memory-mapped output FIFO.

## 9. Memory

- The accelerator owns its own LUT BRAM and its own bit buffer register.
- Input and output live in system memory. The CPU (or DMA) is responsible
  for moving them.

## 10. Communication Overhead

For a bzip2 block emitting `N` symbols:
- LUT upload: `2^MAX_BITS` writes × 32 bits = up to 128 KB per group.
- Byte input: input_bytes × 8 bits.
- Symbol output: `N` × 21 bits.

At 200 MHz and AXI4-Stream 32-bit link:
- Per-symbol output BW = 32 bits × 66 M symbols/s (v1) = 260 MB/s worst
  case, well within a 32-bit / 200 MHz stream (= 6.4 Gb/s). Values are
  ESTIMATES.

## 11. Python Integration (PROPOSED)

A CPython C extension (`_pyflate_accel`) would expose a class:

```python
class HardwareHuffmanTable:
    def upload(self, table_entries: list[tuple[int, int, int]]) -> None: ...
    def decode(self, in_bytes: bytes, max_symbols: int) -> list[tuple[int, int]]: ...
```

`decode()` blocks until `done` is asserted, then reads back the output
FIFO into a Python list. Software falls back to
`HuffmanTable.find_next_symbol` on `error`. This matches the code layout
of the software attempts, so switching between backends is a one-line
change in `decode_huffman_block`.

## 12. Execution Sequence

```
Python                                CPU driver                  Accelerator
──────                                ──────────                  ───────────
build canonical table
  │
  ▼ upload(table_entries)
                                     write TABLE_ADDR/DATA per entry ▶
                                                                     │  LUT loaded
open input file                                                      │
  │                                                                  │
  ▼ decode(compressed, max_symbols=N)
                                     write MAX_SYMBOLS = N
                                     write CTRL[0] = 1  (start)      │
                                                                     ▼  session runs
                                     push bytes on AXI4-Stream        emits symbols
                                                                     │
                                     pop symbols from OUTPUT_FIFO    ◀ done pulses
  ◀ return list[(symbol, bits)]
```

## 13. Implemented vs Proposed

IMPLEMENTED IN RTL:
- `huff_lut`, `bit_shifter`, `huffman_decoder`.
- Direct port-level interface (no MMIO wrapper).
- Self-checking testbenches; simulation runner
  (`subPyflate/hw/run_sim.sh`).

PROPOSED SYSTEM INTEGRATION (not implemented, no code exists):
- MMIO register map above.
- AXI4-Stream / AXI4-Lite wrappers.
- DMA engine for zero-copy byte input.
- Python C-extension driver.

No claim is made that a real driver exists, that a real interrupt fires,
or that end-to-end measured hardware speedup has been captured.
