# Pyflate — RTL Implementation

## 1. Modules

All files are under `Project/subPyflate/hw/rtl/` and `Project/subPyflate/hw/tb/`.

| File | Role |
|---|---|
| `rtl/huff_lut.sv` | Synchronous BRAM-shaped Huffman lookup table. One write port (CPU) and one read port (decoder). Depth `1<<MAX_BITS`, entry `{code_bits[4:0], symbol[15:0]}`. |
| `rtl/bit_shifter.sv` | MSB-first rolling bit buffer that mirrors software `RBitfield`. Exposes `snoop`/`snoop_ready`/`consume`/`byte_valid`/`byte_ready`. Buffer width `BUF_W = 32`. |
| `rtl/huffman_decoder.sv` | Top FSM. Ties LUT + shifter, tracks `symbols_left`, emits `symbol_valid` per decoded symbol, raises `done`/`error`. |
| `tb/tb_huff_lut.sv` | Write / read / verify on a small LUT. |
| `tb/tb_bit_shifter.sv` | Snoop / consume / refill vs an in-testbench software mirror of `RBitfield`. |
| `tb/tb_huffman_decoder.sv` | End-to-end decode of the byte stream `[0x1B, 0x73, 0xA0]` with a hand-derived 5-symbol canonical Huffman table; checks the emitted symbol sequence `[0,1,2,3,4,0,4,1]` exactly. |

## 2. Interfaces

- `huff_lut` — see `docs/10_hardware_architecture.md` §3 for signal
  widths.
- `bit_shifter` — same file, §§3 and 5.
- `huffman_decoder` — same file, §§3 and 4.

Every interface follows the "valid + data + ready" convention where
back-pressure matters (byte input) and pulse-style signaling where it
doesn't (start / done / error / symbol_valid).

## 3. Datapath Summary

For each decoded symbol:
1. `bit_shifter` presents `snoop = buffer[bits_avail-1 -: MAX_BITS]`.
2. `huff_lut` returns `(symbol, code_bits) = mem[snoop]` one cycle later.
3. `huffman_decoder` outputs `symbol_valid`, sets `bs_consume = code_bits`.
4. `bit_shifter` drops the top `code_bits` bits on the next posedge; it
   also accepts one refill byte in the same cycle if `byte_valid` is high
   and there is room.

## 4. Control Summary

Three-state FSM (`S_IDLE` → `S_ISSUE` → `S_WAIT` → `S_CONSUME` → `S_ISSUE`
→ …). See `docs/10_hardware_architecture.md` §6 for the transition table.

The FSM also latches an `error` flag when the LUT returns `code_bits == 0`
(an unused slot), which the driver interprets as "fall back to the
software canonical scan for this one symbol".

## 5. Pipeline

The v1 FSM decodes ~1 symbol per 3 clocks. A pipelined v2 (documented in
`docs/13_hardware_performance.md`) targets 1 symbol per clock.

## 6. Verification Strategy

- **Unit level**: each subordinate module has its own testbench with a
  software-mirror reference:
  - `tb_huff_lut` verifies write→read equivalence.
  - `tb_bit_shifter` maintains a scalar reference buffer that mirrors
    `RBitfield` and compares snoop/bits_avail after every push and
    consume.
- **End-to-end**: `tb_huffman_decoder` uses a hand-designed 5-symbol
  canonical Huffman table plus a hand-computed byte stream. The full
  decoded sequence is compared exactly against the reference (`[0, 1, 2,
  3, 4, 0, 4, 1]`) and the `error` output is checked.

Every testbench prints per-check PASS/FAIL and a final
`RESULT: ALL PASS` / `RESULT: FAILURES=N` line, matching the format used
by `Project/subRay/hw/results/SIMULATION_RESULTS.txt`.

## 7. Simulation Commands

`Project/subPyflate/hw/run_sim.sh` picks the first available simulator (ModelSim,
Icarus Verilog, or Verilator) and runs every testbench in sequence,
writing per-testbench logs into `Project/subPyflate/hw/results/` and a summary
into `SIMULATION_RESULTS.txt`.

For ModelSim (matching the raytrace project's flow):

```
cd Project/subPyflate/hw
vlib work
vlog -sv rtl/huff_lut.sv rtl/bit_shifter.sv rtl/huffman_decoder.sv \
     tb/tb_huff_lut.sv tb/tb_bit_shifter.sv tb/tb_huffman_decoder.sv
vsim -c -do "run -all; quit -f" work.tb_huff_lut
vsim -c -do "run -all; quit -f" work.tb_bit_shifter
vsim -c -do "run -all; quit -f" work.tb_huffman_decoder
```

## 8. What Is Implemented vs Proposed

Implemented (RTL + testbench under `Project/subPyflate/hw/`):
- `huff_lut`, `bit_shifter`, `huffman_decoder` modules.
- Self-checking testbenches per module.
- Simulation runner (`run_sim.sh`) that picks a simulator and produces a
  summary log.

Proposed (documented, not implemented):
- MMIO register map / AXI4-Lite wrapper for CPU-side integration.
- DMA engine for byte-stream input and symbol-stream output.
- Python C-extension / driver that presents `HuffmanTable.find_next_symbol`
  as a hardware-backed callable.
- Multi-lane / pipelined v2 architecture.
