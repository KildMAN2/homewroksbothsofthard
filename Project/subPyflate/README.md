# Pyflate Benchmark Project (HWSW Optimization + Analysis + Hardware Acceleration)

Benchmark #2 for the HWSW project. Companion to `Project/subRay/`.

## 1. Project Overview

Works on the pyperformance pyflate benchmark. Same workflow as
`Project/subRay/`:
- understand the original benchmark,
- collect profiling evidence,
- identify the bottleneck (`HuffmanTable.find_next_symbol`),
- implement three focused software optimization attempts,
- compare measured performance to the target `>= 7%`,
- design and implement a hardware accelerator (canonical Huffman
  decoder + rolling bit shifter),
- report measured software and simulated hardware evidence with clear
  estimate boundaries.

## 2. Repository Structure

```
Project/subPyflate/
├── docs/                     step-by-step documentation (plan + 01..14)
├── original/bm_pyflate/      preserved pyperformance pyflate source
├── optimized/
│   ├── attempt1/             canonical Huffman LUT
│   ├── attempt2/             + MTF pop/insert, BWT counts, _INT2BYTE
│   ├── attempt3/             + hot-loop attribute hoisting + RLE
│   └── final/                copy of the selected attempt (default: 3)
├── profiling/                perf + py-spy artifacts (VM output)
├── results/                  baseline + per-attempt correctness + official
├── reports/                  consolidated report_pyflate.md
├── scripts/                  orchestrator + per-target scripts
├── hw/
│   ├── rtl/                  SystemVerilog RTL
│   ├── tb/                   SystemVerilog testbenches
│   ├── run_sim.sh            picks ModelSim / Icarus / Verilator
│   └── results/              simulation logs
├── prompts/                  prompts.md (AI prompts used)
└── logs/                     environment and command captures
```

## 3. Original Benchmark

Preserved source:
- `Project/subPyflate/original/bm_pyflate/run_benchmark.py`
- `Project/subPyflate/original/bm_pyflate/pyproject.toml`

Workload: `interpreter.tar.bz2` shipped with pyperformance. MD5 gate
`afa004a630fe072901b1d9628b960974`.

## 4. Software Optimization

- `optimized/attempt1/` — canonical Huffman lookup table
  (`HuffmanTable.find_next_symbol`).
- `optimized/attempt2/` — `move_to_front` uses pop/insert; `bwt_transform`
  builds `base[]` with a single-pass count; `int2byte` precomputed.
- `optimized/attempt3/` — attribute hoisting inside `decode_huffman_block`;
  end-of-block RLE uses direct integer indexing on the `bytes` object.
- `optimized/final/` — copy of Attempt 3 (confirmed by the Windows
  preliminary run; see `results/windows_preliminary.txt`).

Every attempt goes through `scripts/check_attempt_correctness.py`:
byte-for-byte match against the preserved original + the pyflate reference
MD5 `afa004a630fe072901b1d9628b960974`.

### Windows preliminary results (2026-09-20)

Run with `scripts/windows_bench.py` on Python 3.12.10 (8 iterations, 3
loops each, `time.perf_counter` around `bzip2_main`). All four attempts
pass correctness. These are NOT the official VM numbers; VM run is
pending course-account access. Full data in
`results/windows_preliminary.txt`.

| Version | Mean (s) | Δ vs original |
|---|---:|---:|
| original | 1.8877 | — |
| attempt1 (LUT alone) | 2.4883 | **-31.82%** (regression, see below) |
| attempt2 | 1.7626 | +6.63% |
| attempt3 | 1.6855 | +10.71% |
| final (= attempt3) | 1.6394 | **+13.16%** — above the 7% target |

Interesting finding: Attempt 1 (LUT alone) regresses because
`_build_lut` runs in Python and fills up to `2**max_bits` entries per
Huffman group. Attempts 2 and 3 remove enough surrounding interpreter
overhead that the LUT's algorithmic advantage nets out. This finding
directly strengthens the hardware story — HW BRAM has O(1) load AND
O(1) lookup.

## 5. Profiling

Everything under `profiling/` is produced by
`Project/subPyflate/scripts/run_profile.sh` (and by `run_baseline.sh` for the
baseline capture). Artifacts:
- `perf_baseline.data`, `perf_report_baseline.txt`, `perf_stat_baseline.txt`
- `perf_report_suite_{baseline,attempt1..3,final}.txt`
  (matched-methodology captures via `profile-suite`)
- `flamegraph_pyspy_baseline.svg`,
  `flamegraph_pyspy_{attempt1..3,final}.svg`

## 6. Hardware Acceleration

Selected kernel: canonical Huffman decoder with rolling MSB-first bit
buffer (mirrors bzip2's `RBitfield.readbits/snoopbits`).

Implemented RTL:
- `hw/rtl/huff_lut.sv`
- `hw/rtl/bit_shifter.sv`
- `hw/rtl/huffman_decoder.sv`

Verification and evidence:
- `hw/tb/tb_huff_lut.sv`
- `hw/tb/tb_bit_shifter.sv`
- `hw/tb/tb_huffman_decoder.sv`
- `hw/run_sim.sh` (autodetects ModelSim / Icarus / Verilator)
- `hw/results/SIMULATION_RESULTS.txt` — Icarus Verilog 12.0 on Windows,
  **22/22 checks pass** across the three testbenches.

Evidence boundary:
- IMPLEMENTED: RTL modules + testbenches above.
- SIMULATED: Icarus Verilog 12.0 (2026-09-21) — 22/22 checks pass, see
  `SIMULATION_RESULTS.txt`.
- ESTIMATED (not measured): 200 MHz target clock, cycles/symbol,
  throughput, Amdahl speedups, area, power, bandwidth — see
  `docs/13_hardware_performance.md`.
- PROPOSED (not implemented): MMIO / AXI-Lite / AXI-Stream, DMA,
  Python C-extension driver — see `docs/12_hw_sw_interface.md`.

No claim of synthesis, FPGA deployment, real HW/SW integration runtime,
measured area, measured power, measured operating frequency, or measured
hardware speedup.

## 7. How To Reproduce

Run from repository root on a Linux VM with bash, perf, python3-dbg, and
pyperformance installed. Main orchestrator:

```
bash Project/subPyflate/scripts/script_pyflate.sh              # defaults to 'all'
bash Project/subPyflate/scripts/script_pyflate.sh baseline
bash Project/subPyflate/scripts/script_pyflate.sh attempt1
bash Project/subPyflate/scripts/script_pyflate.sh optimize
bash Project/subPyflate/scripts/script_pyflate.sh profile
bash Project/subPyflate/scripts/script_pyflate.sh profile-suite
bash Project/subPyflate/scripts/script_pyflate.sh check
bash Project/subPyflate/scripts/script_pyflate.sh compare
```

Environment variables (subset):
- `RUNS` — perf stat repetitions (default: 3).
- `PROFILE_TARGET` — baseline | attempt1 | attempt2 | attempt3 | final.
- `PROFILE_USE_FAST` — 0 or 1 (default for `profile`: 0).
- `OPTIMIZE_USE_FAST` — 0 or 1 (append `--fast` to a direct final run).

Correctness checks (any of these, or `... script_pyflate.sh check`):
```
python3 Project/subPyflate/scripts/check_attempt1_correctness.py
python3 Project/subPyflate/scripts/check_attempt2_correctness.py
python3 Project/subPyflate/scripts/check_attempt3_correctness.py
python3 Project/subPyflate/scripts/check_final_correctness.py
```

Hardware simulation:
```
bash Project/subPyflate/hw/run_sim.sh                    # all three testbenches
bash Project/subPyflate/hw/run_sim.sh tb_huffman_decoder # one testbench
```

## 8. Main Report

- Primary consolidated report: `Project/subPyflate/reports/report_pyflate.md`
  (mirrored to `.txt`).

## 9. AI Prompts

- `Project/subPyflate/prompts/prompts.md`

## Notes For Course Staff

This subproject keeps measured software results, simulated hardware
results, and projected hardware estimates separated:
- Measured software official comparison: `results/original_official.txt`
  and `results/final_official.txt`.
- Simulated hardware verification: `hw/results/`.
- Hardware acceleration estimates: `docs/13_hardware_performance.md`.

`TO BE COLLECTED IN VM` markers in this repository identify values that
are filled in after the VM run and are never invented.
