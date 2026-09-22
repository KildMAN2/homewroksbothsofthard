# Pyflate Benchmark Project

**HWSW Benchmark Optimization, Profiling, and Hardware Acceleration**

This directory contains the complete Pyflate subproject for the HWSW performance-engineering project. It is the second benchmark in the repository and follows the same evidence-driven workflow as `Project/subRay/`, while using Pyflate-specific profiling, software optimizations, and hardware acceleration.

The project starts from the untouched `pyperformance` `pyflate` benchmark, profiles its real bzip2 decompression workload, implements and measures three cumulative software optimizations, verifies correctness against the benchmark's reference output, and then designs and simulates a SystemVerilog Huffman-decoding accelerator.

---

## 1. Project Status

The Pyflate subproject is complete at the software-measurement and RTL-simulation level.

### Main measured software result

Course VM comparison:

| Version | Elapsed Time | Result |
|---|---:|---:|
| Original | `120.99 ± 6.80 s` | baseline |
| Final | `76.307 ± 0.236 s` | optimized |
| Speedup | `1.586×` | |
| Runtime improvement | **36.93%** | target achieved |

The project target was at least `7%` improvement, so the measured VM result exceeds the requirement by a large margin.

The final implementation follows the cumulative **Attempt 3** optimization line.

### Windows cross-check

A separate non-fast pyperformance measurement on Windows / CPython 3.12 produced:

| Version | Mean |
|---|---:|
| Original | `516 ms ± 29 ms` |
| Final | `362 ms ± 22 ms` |
| Improvement | **29.84%** |
| Speedup | `~1.425×` |

The Windows and VM numbers are intentionally kept separate because the host, Python build, and run mode differ.

---

## 2. Benchmark Overview

`pyflate` is a pure-Python decompression benchmark from `pyperformance`.

For this project, the benchmark decompresses:

```text
interpreter.tar.bz2
```

The timed path does not call Python's native `bz2` module. The bzip2 decoding logic is implemented in Python and includes:

- MSB-first bit-field reading,
- bzip2 block parsing,
- symbol-presence decoding,
- selector decoding,
- canonical Huffman-code construction,
- Huffman symbol lookup,
- RUNA/RUNB handling,
- move-to-front decoding,
- inverse Burrows-Wheeler transform,
- final run-length expansion.

The benchmark also contains a gzip/DEFLATE path, but the fixed project input is bzip2, so that path is not part of the measured workload.

### Real workload characteristics

The preserved benchmark input has the following measured properties:

| Quantity | Value |
|---|---:|
| Compressed input size | `67,562 bytes` |
| Decompressed output size | `399,360 bytes` |
| Compression ratio | `5.91×` |
| bzip2 blocks | `2` |
| Huffman symbol lookups | `296,542` |
| Move-to-front calls | `185,606` |
| `readbits()` calls | `313,416` |
| Total bits consumed through bit reader | `1,080,992` |
| Reference MD5 | `afa004a630fe072901b1d9628b960974` |

The original workload therefore performs hundreds of thousands of tiny Python-level operations on bits, bytes, lists, and Huffman-table entries.

---

## 3. Repository Structure

```text
Project/subPyflate/
├── README.md
│
├── docs/
│   ├── 00_project_plan.md
│   ├── 01_understanding.md
│   ├── 02_baseline.md
│   ├── 03_profiling.md
│   ├── 04_bottleneck_analysis.md
│   ├── 05_optimization.md
│   ├── 06_final_software.md
│   ├── 07_before_after_profiling.md
│   ├── 08_consistency_audit.md
│   ├── 09_hardware_candidate.md
│   ├── 10_hardware_architecture.md
│   ├── 11_rtl_implementation.md
│   ├── 12_hw_sw_interface.md
│   ├── 13_hardware_performance.md
│   └── 14_final_audit.md
│
├── original/
│   └── bm_pyflate/
│       ├── run_benchmark.py
│       ├── pyproject.toml
│       └── data/
│           └── interpreter.tar.bz2
│
├── optimized/
│   ├── attempt1/
│   ├── attempt2/
│   ├── attempt3/
│   └── final/
│
├── profiling/
│   ├── perf_baseline.data
│   ├── perf_final.data
│   ├── perf/stat/report text outputs
│   ├── flamegraph_pyspy_baseline.svg
│   ├── flamegraph_pyspy_attempt1.svg
│   ├── flamegraph_pyspy_attempt2.svg
│   ├── flamegraph_pyspy_attempt3.svg
│   └── flamegraph_pyspy_final.svg
│
├── results/
│   ├── baseline/
│   ├── attempt1/
│   ├── attempt2/
│   ├── attempt3/
│   ├── final/
│   ├── original_official.txt
│   └── final_official.txt
│
├── reports/
│   ├── report_pyflate.md
│   ├── report_pyflate.txt
│   ├── baseline_results.txt
│   └── final_performance_comparison.txt
│
├── scripts/
│   ├── script_pyflate.sh
│   ├── run_baseline.sh
│   ├── run_attempt1.sh
│   ├── run_profile.sh
│   ├── generate_flamegraph.sh
│   ├── check_attempt1_correctness.py
│   ├── check_attempt2_correctness.py
│   ├── check_attempt3_correctness.py
│   └── check_final_correctness.py
│
├── hw/
│   ├── rtl/
│   │   ├── huff_lut.sv
│   │   ├── bit_shifter.sv
│   │   └── huffman_decoder.sv
│   ├── tb/
│   │   ├── tb_huff_lut.sv
│   │   ├── tb_bit_shifter.sv
│   │   └── tb_huffman_decoder.sv
│   ├── run_sim.sh
│   └── results/
│       └── SIMULATION_RESULTS.txt
│
├── prompts/
│   ├── prompts.md
│   └── subPyflate_prompts.md
│
└── presentation/
    └── ...
```

---

## 4. Preserved Original Benchmark

The untouched benchmark is stored under:

```text
Project/subPyflate/original/bm_pyflate/
```

Important files:

```text
run_benchmark.py
pyproject.toml
data/interpreter.tar.bz2
```

All software optimization work is kept outside `original/`.

This separation is important because every optimized result can be compared directly against the preserved benchmark.

---

## 5. Correctness Policy

Performance improvements are accepted only if correctness is preserved.

The benchmark's reference MD5 is:

```text
afa004a630fe072901b1d9628b960974
```

The project adds an external correctness check on top of the benchmark's own internal assertion.

Each accepted optimization must satisfy:

```text
IDENTICAL=YES
MATCHES_REFERENCE=YES
```

The checker decompresses the same input with the preserved original and the optimized module, compares the bytes exactly, and checks the reference digest.

This was done for:

- Attempt 1,
- Attempt 2,
- Attempt 3,
- Final.

---

## 6. Profiling Methodology

The project uses several profiling tools because no single tool gives the entire picture.

### pyperformance / pyperf

Used for repeatable benchmark timing and statistical summaries.

### Linux perf

Used for:

- `perf stat`,
- `perf record`,
- `perf report`,
- low-level instruction/branch/cache evidence.

### py-spy

Used for Python-frame flame graphs.

The project preserves flame graphs for:

- baseline,
- Attempt 1,
- Attempt 2,
- Attempt 3,
- final.

### Evidence policy

Profiling statements are kept separate from interpretation.

For example, `_PyEval_EvalFrameDefault` can become a larger **percentage** of the final profile even while the total execution time drops substantially. A larger relative share does not automatically mean that the function became slower.

---

## 7. Original Bottlenecks

The original VM `perf report` includes the following important self-time entries:

| Symbol / Cost Family | Baseline Self Time |
|---|---:|
| `_PyEval_EvalFrameDefault` | `22.81%` |
| `_PyMem_DebugCheckAddress` | `4.06%` |
| `__memset_avx2_unaligned_erms` | `3.11%` |
| `read_size_t` | `2.75%` |
| `call_function` | `2.56%` |
| `list_dealloc` | `2.33%` |
| `list_ass_slice` | `1.96%` |

The profiling and source analysis identified several important cost sources:

1. repeated Python interpreter dispatch,
2. linear Huffman symbol lookup,
3. move-to-front list reconstruction,
4. repeated list allocation/deallocation,
5. repeated BWT-related searches,
6. repeated tiny byte conversions,
7. attribute lookup inside hot loops.

A particularly useful result is the connection between the original move-to-front implementation and the profiler:

```text
list_dealloc      2.33%
list_ass_slice    1.96%
```

Those costs drop out of the final top-cost list after the MTF rewrite.

---

## 8. Software Optimization Attempts

Unlike the Raytrace subproject, the Pyflate attempts are **cumulative**.

Attempt 2 starts from Attempt 1, and Attempt 3 starts from Attempt 2.

### Attempt 1 — Canonical Huffman Lookup Table

Target:

```text
HuffmanTable.find_next_symbol()
```

Original behavior:

- repeatedly scans a Python list of Huffman codes,
- peeks at bits,
- compares entries until a match is found.

Optimization:

- build a canonical lookup table indexed by upcoming bits,
- cache the table,
- replace repeated linear scans with near-O(1) lookup,
- preserve fallback behavior for edge cases.

This optimization is algorithmically attractive, but it exposed an important Python-specific trade-off: building a large lookup table in Python is itself expensive.

### Attempt 2 — MTF, BWT, and `_INT2BYTE`

Attempt 2 adds:

#### Move-to-front

Original style reconstructs a list through slices.

Optimized style uses:

```python
l.insert(0, l.pop(c))
```

This removes repeated slice creation and list reconstruction.

#### BWT setup

Repeated `bytes.find()` scanning is replaced with a single counting pass plus cumulative positions.

#### Byte conversion

A precomputed table:

```text
_INT2BYTE
```

replaces repeated small `struct.pack` work.

### Attempt 3 — Hot-Loop Hoisting and RLE Cleanup

Attempt 3 further reduces interpreter work by binding stable operations to locals inside the hottest loop.

Examples include:

- Huffman lookup method,
- list `pop`,
- list `insert`,
- output `append`,
- `_INT2BYTE`.

It also tightens the final run-length expansion by directly indexing the `bytes` object instead of repeatedly creating one-byte slices.

### Final

The final implementation follows the Attempt 3 cumulative line.

---

## 9. Why Attempt 1 Can Look Worse in a Cold Run

One of the most useful findings in this project is that a theoretically better algorithm can still regress when implemented in pure Python.

A simple cold `time.perf_counter` measurement showed Attempt 1 slower than the original because the lookup-table construction itself fills many entries in Python.

Cold/custom preliminary result:

| Version | Mean | Change vs Original |
|---|---:|---:|
| Original | `1.8877 s` | — |
| Attempt 1 | `2.4883 s` | `-31.82%` |
| Attempt 2 | `1.7626 s` | `+6.63%` |
| Attempt 3 | `1.6855 s` | `+10.71%` |
| Final | `1.6394 s` | `+13.16%` |

However, pyperformance's warmed/calibrated repeated-loop methodology amortizes setup cost differently.

With pyperformance `--fast` on Windows:

| Version | Mean | Change vs Original |
|---|---:|---:|
| Baseline | `540 ms ± 24 ms` | — |
| Attempt 1 | `453 ms ± 17 ms` | `+16.1%` |
| Attempt 2 | `354 ms ± 9 ms` | `+34.4%` |
| Attempt 3 | `324 ms ± 6 ms` | `+40.0%` |
| Final | `348 ms ± 22 ms` | `+35.6%` |

This difference is documented rather than hidden.

It also motivates the hardware proposal: BRAM lookup avoids Python's table-lookup and interpreter overhead.

---

## 10. Official Course-VM Performance

Environment:

```text
Ubuntu 22.04.5 LTS
CPython python3-dbg 3.10.12
perf 5.15.209
pyperformance 1.14.0
QEMU/KVM with PMU passthrough
```

Measured with:

```text
perf stat -r 3
```

using the matched original/final benchmark workflow.

### Original

```text
Elapsed time:      120.99 ± 6.80 s
Task clock:        113,777 ms
Instructions:      579,459,257,273
Branches:          142,417,577,761
Branch misses:     770,743,225
Cache references:  543,649,894
Cache misses:      28,010,769
Page faults:       463,011
Context switches:  3,089
```

### Final

```text
Elapsed time:      76.307 ± 0.236 s
Task clock:        76,417 ms
Instructions:      388,984,213,555
Branches:          94,689,052,878
Branch misses:     479,262,450
Cache references:  410,288,916
Cache misses:      28,422,250
Page faults:       458,789
Context switches:  2,888
```

### Improvement

| Metric | Change |
|---|---:|
| Wall-clock runtime | **-36.93%** |
| Speedup | **1.586×** |
| Instructions | **-32.87%** |
| Branches | **-33.51%** |
| Branch misses | **-37.82%** |
| Cache references | **-24.53%** |
| Cache misses | `+1.47%` |
| Page faults | `-0.91%` |
| Context switches | `-6.51%` |

The strongest evidence is the large reduction in executed instructions and branches, which is consistent with removing Python-level work from the hot decode loops.

### PMU limitation

The `cycles` counter reports `0` in this KVM environment.

This is documented as a PMU limitation.

It is **not** interpreted as the benchmark executing in zero CPU cycles.

---

## 11. Before/After Profiling Result

VM perf sampling:

```text
Baseline top:
_PyEval_EvalFrameDefault 22.81%

Final top:
_PyEval_EvalFrameDefault 24.26%
```

The interpreter loop becomes a slightly larger fraction of the final run, but the final run is much shorter.

That is expected: other overhead has been removed, so the remaining irreducible interpreter loop occupies a larger percentage of a smaller total.

Evidence for the MTF optimization is clearer:

```text
list_dealloc:
baseline 2.33%
final: dropped out of the top 15

list_ass_slice:
baseline 1.96%
final: dropped out of the top 15
```

---

## 12. Hardware Acceleration Candidate

The selected hardware kernel is the:

# Canonical Huffman Decoder

The hardware accelerator mirrors the hottest decode operation using:

1. a BRAM-shaped Huffman lookup table,
2. an MSB-first rolling bit buffer,
3. a control FSM.

This is a strong hardware candidate because the work is:

- repeated hundreds of thousands of times,
- dominated by bit manipulation and lookup,
- exact integer/bit logic,
- suitable for BRAM,
- suitable for pipelining,
- independent of floating-point arithmetic.

Other candidates considered include:

- inverse BWT,
- move-to-front,
- RLE output logic.

The Huffman decoder provides the best balance of measured relevance, regularity, and implementation scope.

---

## 13. SystemVerilog Architecture

Implemented RTL:

```text
hw/rtl/huff_lut.sv
hw/rtl/bit_shifter.sv
hw/rtl/huffman_decoder.sv
```

### `huff_lut`

Stores canonical Huffman decode entries.

The interface supports:

- table writes,
- decode reads,
- symbol output,
- code-length output.

### `bit_shifter`

Implements the rolling MSB-first bit buffer corresponding to the software `RBitfield`.

Responsibilities:

- accept compressed bytes,
- expose upcoming bits,
- consume decoded code bits,
- refill the buffer.

### `huffman_decoder`

Top-level controller tying the LUT and bit shifter together.

The current v1 uses an FSM similar to:

```text
IDLE
  ↓
ISSUE
  ↓
WAIT
  ↓
CONSUME
  ├── next symbol → ISSUE
  └── final symbol → IDLE
```

Current design target:

```text
~1 symbol / 3 clocks
```

A deeper pipelined architecture targeting one symbol per cycle is documented as proposed future work, not implemented v1 behavior.

---

## 14. RTL Verification

Simulation was run using:

```text
Icarus Verilog 12.0
```

Result:

```text
22 / 22 checks passed
0 functional errors
```

Breakdown:

| Testbench | Checks | Result |
|---|---:|---|
| `tb_huff_lut` | 5 | PASS |
| `tb_bit_shifter` | 8 | PASS |
| `tb_huffman_decoder` | 9 | PASS |
| **Total** | **22** | **ALL PASS** |

The end-to-end decoder test loads a known canonical Huffman table, streams:

```text
0x1B 0x73 0xA0
```

and verifies the exact decoded sequence:

```text
[0, 1, 2, 3, 4, 0, 4, 1]
```

Simulation validates logical RTL behavior.

It does **not** provide:

- synthesis timing,
- real FPGA frequency,
- physical area,
- measured power,
- hardware-in-the-loop speedup.

---

## 15. Hardware / Software Boundary

### Implemented

Currently implemented:

- `huff_lut`,
- `bit_shifter`,
- `huffman_decoder`,
- direct RTL ports,
- self-checking testbenches.

### Proposed

Not implemented:

- AXI4-Lite/MMIO wrapper,
- AXI4-Stream interface,
- DMA engine,
- Python C extension,
- device driver,
- physical FPGA integration.

### Proposed execution flow

```text
Python software
   │
   ├── parse bzip2 headers
   ├── build canonical Huffman table
   ├── upload LUT
   └── submit compressed bytes
          │
          ▼
   +----------------------+
   | Huffman accelerator  |
   |                      |
   |  bit_shifter         |
   |       ↓              |
   |  huff_lut            |
   |       ↓              |
   |  FSM / decoder       |
   +----------------------+
          │
          ▼
decoded symbols
          │
          ▼
Python continues:
MTF → inverse BWT → RLE
```

---

## 16. Hardware Performance Estimates

Hardware performance values are estimates only.

The project does **not** claim measured accelerator speedup.

Assumed target for analysis:

```text
200 MHz
```

Estimated v1:

```text
~1 symbol / 3 cycles
~66 M symbols/s at 200 MHz
```

Proposed pipelined v2:

```text
~1 symbol / cycle
~200 M symbols/s at 200 MHz
```

Amdahl's Law is used for system-level estimates:

```text
Speedup = 1 / ((1 - P) + P/S)
```

where:

- `P` is the fraction of execution that could be accelerated,
- `S` is the accelerator's speedup for that fraction.

Every hardware number that has not been measured on real hardware is labeled **ESTIMATE** in the project documentation.

---

## 17. How to Reproduce

Run commands from the repository root.

### First-time setup (install dependencies)

```bash
bash Project/subPyflate/scripts/script_pyflate.sh setup
```

This detects the OS/package manager and installs the system packages (`python3`, `python3-pip`, `python3-dbg`, `perf`/`linux-tools`, `git`), the Python tools (`pyperformance`, `pyperf`, `py-spy`), and clones FlameGraph into `$HOME/FlameGraph`. Flame-graph generation also detects `/opt/FlameGraph` or a `FLAMEGRAPH_DIR` override.

### Main orchestrator

```bash
bash Project/subPyflate/scripts/script_pyflate.sh
```

Useful modes:

```bash
bash Project/subPyflate/scripts/script_pyflate.sh setup
bash Project/subPyflate/scripts/script_pyflate.sh baseline
bash Project/subPyflate/scripts/script_pyflate.sh attempt1
bash Project/subPyflate/scripts/script_pyflate.sh optimize
bash Project/subPyflate/scripts/script_pyflate.sh profile
bash Project/subPyflate/scripts/script_pyflate.sh profile-suite
bash Project/subPyflate/scripts/script_pyflate.sh check
bash Project/subPyflate/scripts/script_pyflate.sh compare
```

### Correctness checks

```bash
python3 Project/subPyflate/scripts/check_attempt1_correctness.py
python3 Project/subPyflate/scripts/check_attempt2_correctness.py
python3 Project/subPyflate/scripts/check_attempt3_correctness.py
python3 Project/subPyflate/scripts/check_final_correctness.py
```

### Hardware simulation

Run all hardware testbenches:

```bash
bash Project/subPyflate/hw/run_sim.sh
```

Run only the top decoder test:

```bash
bash Project/subPyflate/hw/run_sim.sh tb_huffman_decoder
```

---

## 18. Main Evidence Files

### Software result

```text
Project/subPyflate/results/original_official.txt
Project/subPyflate/results/final_official.txt
Project/subPyflate/reports/final_performance_comparison.txt
```

### Profiling

```text
Project/subPyflate/profiling/
```

Important artifacts include:

```text
vm_perf_report_baseline.txt
vm_perf_report_final.txt
flamegraph_pyspy_baseline.svg
flamegraph_pyspy_final.svg
```

### Correctness

```text
Project/subPyflate/results/attempt1/correctness_report.txt
Project/subPyflate/results/attempt2/correctness_report.txt
Project/subPyflate/results/attempt3/correctness_report.txt
Project/subPyflate/results/final/correctness_report.txt
```

### Hardware

```text
Project/subPyflate/hw/results/SIMULATION_RESULTS.txt
```

### Final report

```text
Project/subPyflate/reports/report_pyflate.md
Project/subPyflate/reports/report_pyflate.txt
```

### AI prompt record

```text
Project/subPyflate/prompts/subPyflate_prompts.md
```

---

## 19. Documentation Map

For a full technical walkthrough, read the files in this order:

1. `docs/01_understanding.md`
2. `docs/02_baseline.md`
3. `docs/03_profiling.md`
4. `docs/04_bottleneck_analysis.md`
5. `docs/05_optimization.md`
6. `docs/06_final_software.md`
7. `docs/07_before_after_profiling.md`
8. `docs/09_hardware_candidate.md`
9. `docs/10_hardware_architecture.md`
10. `docs/11_rtl_implementation.md`
11. `docs/12_hw_sw_interface.md`
12. `docs/13_hardware_performance.md`
13. `reports/report_pyflate.md`

---

## 20. Evidence Boundaries

The project intentionally distinguishes four categories.

### MEASURED SOFTWARE

Real benchmark/profiling results from Windows and the course VM.

Examples:

```text
120.99 s → 76.307 s
36.93% improvement
1.586× speedup
```

### SIMULATED RTL

Logical verification from SystemVerilog simulation.

Example:

```text
22 / 22 checks passed
```

### ESTIMATED HARDWARE

Examples:

```text
200 MHz target
66 M symbols/s v1
200 M symbols/s proposed v2
Amdahl speedup estimates
area/power estimates
```

These are not measured hardware results.

### PROPOSED SYSTEM INTEGRATION

Not implemented:

```text
MMIO
AXI
DMA
Python C extension
device driver
real FPGA integration
```

---

## 21. Known Limitations

The current project does not include:

- synthesis,
- place and route,
- FPGA deployment,
- measured accelerator frequency,
- measured FPGA area,
- measured FPGA power,
- hardware-in-the-loop Pyflate execution,
- measured end-to-end HW/SW speedup,
- implemented MMIO/AXI/DMA integration.

The KVM environment also has a PMU limitation where the `cycles` counter reports zero.

These limitations are documented explicitly rather than being replaced with guessed numbers.

---

## 22. Key Conclusions

Pyflate is dominated by repeated byte/bit-level Python work rather than object-heavy geometry.

The software optimization process produced several useful findings:

- linear Huffman lookup is an obvious algorithmic target,
- a Python LUT can still be expensive to construct,
- MTF slice removal eliminates measurable list-management overhead,
- cumulative optimization substantially reduces instructions and branches,
- the final implementation improves course-VM runtime by **36.93%**.

The hardware portion maps the canonical Huffman-decode operation into a compact streaming architecture built from:

```text
BRAM LUT + rolling bit buffer + FSM
```

The RTL is implemented and simulation-verified, while real system integration and physical hardware performance remain future work.

---

## 23. Companion Benchmark

The first benchmark in the same project is:

```text
Project/subRay/
```

Raytrace and Pyflate were intentionally useful complements:

- **Raytrace:** object-heavy geometry, floating-point arithmetic, repeated intersections.
- **Pyflate:** bit/byte processing, Huffman decoding, list operations, transformation loops.

Together they demonstrate two different software bottleneck classes and two different accelerator styles.
