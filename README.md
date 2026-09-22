# HWSW Benchmark Optimization and Hardware Acceleration

This repository contains coursework plus two completed benchmark projects for software performance analysis, optimization, profiling, and hardware acceleration.

The two final benchmark subprojects are:

- **Raytrace** — `Project/subRay/`
- **Pyflate** — `Project/subPyflate/`

Both projects follow the same evidence-driven workflow:

```text
understand original benchmark
        ↓
measure baseline
        ↓
profile with perf / flame graphs
        ↓
identify measured bottlenecks
        ↓
implement software optimizations
        ↓
verify correctness
        ↓
measure official before/after performance
        ↓
select a hardware acceleration target
        ↓
design SystemVerilog RTL + testbenches
        ↓
simulate
        ↓
document HW/SW interface
        ↓
estimate system-level hardware benefit
```

The repository intentionally separates:

- measured software results,
- simulated RTL results,
- estimated hardware performance,
- proposed system integration.

No FPGA deployment, synthesis timing, measured area, measured power, or measured end-to-end hardware speedup is claimed unless explicitly backed by an artifact.

---

## 1. Repository Layout

```text
homewroksbothsofthard/
├── README.md
├── Project/
│   ├── subRay/
│   │   ├── docs/
│   │   ├── original/
│   │   ├── optimized/
│   │   ├── profiling/
│   │   ├── results/
│   │   ├── reports/
│   │   ├── scripts/
│   │   ├── hw/
│   │   ├── prompts/
│   │   └── presentation/
│   │
│   └── subPyflate/
│       ├── docs/
│       ├── original/
│       ├── optimized/
│       ├── profiling/
│       ├── results/
│       ├── reports/
│       ├── scripts/
│       ├── hw/
│       ├── prompts/
│       └── presentation/
│
├── hw1/
└── hw2/
```

`hw1/` and `hw2/` are earlier coursework directories and are separate from the two final benchmark projects.

---

## 2. Final Results at a Glance

| Benchmark | Original | Final | Improvement | Speedup | Official Final |
|---|---:|---:|---:|---:|---|
| Raytrace | `81.285 s` | `19.7062 s` | **75.76%** | `~4.12×` | Attempt 1 |
| Pyflate | `120.99 s` | `76.307 s` | **36.93%** | `1.586×` | Attempt 3 line |

Both exceed the project target of at least `7%` improvement.

---

# 3. Raytrace

Directory:

```text
Project/subRay/
```

## Software result

Official matched before/after:

```text
Original: 81.285 ± 0.198 s
Final:    19.7062 ± 0.0133 s
```

Result:

```text
Improvement: 75.76%
Speedup:     ~4.12×
```

The official final artifact is based on **Attempt 1**, which scalarizes hot geometry operations and removes large amounts of temporary Python object / method overhead.

Later non-fast measurements found Attempt 3 slightly faster, but Attempt 1 remains the locked official final because the official comparison and submission pipeline were built around it.

## Profiling result

Major original cost families include:

- interpreter dispatch,
- frame creation/destruction,
- float boxing/arithmetic,
- object/method/type lookup,
- repeated geometry-object creation.

Matched perf-stat evidence shows very large reductions in executed work:

- instructions: about `-74.3%`,
- branches: about `-74.9%`,
- branch mispredictions: about `-80.8%`.

## Hardware accelerator

Selected kernel:

```text
sphere / plane intersection
+ closest-hit reduction
+ visibility / any-hit mode
```

Implemented RTL:

```text
Project/subRay/hw/rtl/fxp_sqrt.sv
Project/subRay/hw/rtl/sphere_intersect.sv
Project/subRay/hw/rtl/intersect_accel.sv
```

Numeric format:

```text
Q16.16 fixed-point
```

Simulation result:

```text
ModelSim
18 / 18 checks passed
0 compile errors
0 compile warnings
```

Hardware estimates use Amdahl's Law and an assumed 200 MHz target, but no synthesis or real FPGA timing is claimed.

Full details:

```text
Project/subRay/README.md
Project/subRay/reports/report_raytrace.md
```

---

# 4. Pyflate

Directory:

```text
Project/subPyflate/
```

## Benchmark

Pyflate is a pure-Python bzip2 decompression workload using:

```text
interpreter.tar.bz2
```

Reference output MD5:

```text
afa004a630fe072901b1d9628b960974
```

The measured workload performs:

```text
296,542 Huffman symbol lookups
185,606 move-to-front operations
313,416 readbits() calls
```

## Software result

Course-VM matched result:

```text
Original: 120.99 ± 6.80 s
Final:    76.307 ± 0.236 s
```

Result:

```text
Improvement: 36.93%
Speedup:     1.586×
```

The final implementation follows the cumulative Attempt 3 line:

```text
Attempt 1: canonical Huffman LUT
Attempt 2: + MTF / BWT / _INT2BYTE cleanup
Attempt 3: + hot-loop hoisting / RLE cleanup
```

All accepted attempts match the reference output.

A separate Windows non-fast pyperformance cross-check produced:

```text
516 ms → 362 ms
29.84% improvement
```

The Windows and VM results are kept separate because they use different hosts/interpreters/methods.

## Profiling result

The final version substantially reduces:

- executed instructions,
- branches,
- branch misses,
- list-management overhead.

Measured VM deltas include:

```text
instructions:     -32.87%
branches:         -33.51%
branch misses:    -37.82%
cache references: -24.53%
```

## Hardware accelerator

Selected kernel:

```text
canonical Huffman decoder
```

Implemented modules:

```text
Project/subPyflate/hw/rtl/huff_lut.sv
Project/subPyflate/hw/rtl/bit_shifter.sv
Project/subPyflate/hw/rtl/huffman_decoder.sv
```

Simulation result:

```text
Icarus Verilog 12.0
22 / 22 checks passed
```

The current v1 is an FSM-based streaming decoder; a one-symbol-per-cycle deeper pipeline is documented as future work.

Full details:

```text
Project/subPyflate/README.md
Project/subPyflate/reports/report_pyflate.md
```

---

## 5. Why These Two Benchmarks Complement Each Other

The two benchmarks stress very different parts of CPython.

### Raytrace

Main characteristics:

- object-heavy geometry,
- float arithmetic,
- recursive rendering,
- many ray/object tests,
- method/attribute dispatch,
- temporary object creation.

Software solution:

```text
scalarize hot paths
reduce object/method overhead
```

Hardware direction:

```text
intersection + closest-hit accelerator
```

### Pyflate

Main characteristics:

- bit/byte processing,
- canonical Huffman decoding,
- list manipulation,
- move-to-front,
- inverse BWT,
- RLE,
- tight interpreter loops.

Software solution:

```text
faster Huffman lookup
remove MTF/BWT/byte-conversion overhead
hoist hot-loop operations
```

Hardware direction:

```text
BRAM Huffman LUT
+ rolling bit buffer
+ decoder FSM
```

Together they show two substantially different optimization and accelerator-design styles.

---

## 6. Correctness Policy

Optimization is not accepted based only on timing.

### Raytrace

Software attempts are checked against deterministic rendered output for a fixed test scene/resolution.

Recorded attempts report:

```text
IDENTICAL=YES
```

### Pyflate

Software attempts are checked byte-for-byte against the preserved original and the benchmark reference digest:

```text
afa004a630fe072901b1d9628b960974
```

Expected accepted result:

```text
IDENTICAL=YES
MATCHES_REFERENCE=YES
```

---

## 7. Profiling Tools

The projects use:

### pyperformance / pyperf

Benchmark timing and statistical execution.

### Linux perf

```text
perf stat
perf record
perf report
```

Used for hardware counters and sampled call-stack profiling.

### FlameGraph

Used to visualize perf stack samples.

### py-spy

Used as supplemental Python-frame profiling.

The project does not treat flame-graph height as cost. Width corresponds to sampled runtime share; height corresponds to call-stack depth.

---

## 8. Reproduction

Run from the repository root.

### Raytrace

```bash
bash Project/subRay/scripts/script_raytrace.sh
```

Common modes:

```bash
bash Project/subRay/scripts/script_raytrace.sh baseline
bash Project/subRay/scripts/script_raytrace.sh optimize
bash Project/subRay/scripts/script_raytrace.sh profile
bash Project/subRay/scripts/script_raytrace.sh compare
```

### Pyflate

```bash
bash Project/subPyflate/scripts/script_pyflate.sh
```

Common modes:

```bash
bash Project/subPyflate/scripts/script_pyflate.sh baseline
bash Project/subPyflate/scripts/script_pyflate.sh attempt1
bash Project/subPyflate/scripts/script_pyflate.sh optimize
bash Project/subPyflate/scripts/script_pyflate.sh profile
bash Project/subPyflate/scripts/script_pyflate.sh profile-suite
bash Project/subPyflate/scripts/script_pyflate.sh check
bash Project/subPyflate/scripts/script_pyflate.sh compare
```

---

## 9. Hardware Verification

### Raytrace

```bash
# See Project/subRay/hw/ and its saved ModelSim logs.
```

Result:

```text
18 / 18 checks passed
```

### Pyflate

```bash
bash Project/subPyflate/hw/run_sim.sh
```

Result:

```text
22 / 22 checks passed
```

---

## 10. Reports

Primary reports:

```text
Project/subRay/reports/report_raytrace.md
Project/subPyflate/reports/report_pyflate.md
```

Text mirrors are also included for submission compatibility.

Performance-comparison summaries:

```text
Project/subRay/reports/final_performance_comparison.txt
Project/subPyflate/reports/final_performance_comparison.txt
```

---

## 11. AI Prompt Records

Prompt logs are stored under:

```text
Project/subRay/prompts/
Project/subPyflate/prompts/
```

These document the major AI-assisted workflow stages, including benchmark understanding, profiling, optimization, hardware design, RTL/testbench work, and final documentation.

AI suggestions were treated as engineering proposals rather than measurements. Results were accepted only after running the project’s own correctness and performance checks.

---

## 12. Evidence Boundaries

### MEASURED SOFTWARE

Backed by saved benchmark / perf artifacts.

Examples:

```text
Raytrace: 81.285 s → 19.7062 s
Pyflate:  120.99 s → 76.307 s
```

### SIMULATED RTL

Backed by testbench/simulator logs.

Examples:

```text
Raytrace: 18 / 18 checks passed
Pyflate:  22 / 22 checks passed
```

### ESTIMATED HARDWARE

Not measured on a deployed FPGA.

Includes:

```text
target clocks
cycles/request
throughput
Amdahl speedups
area estimates
power estimates
bandwidth estimates
```

### PROPOSED SYSTEM INTEGRATION

Not currently implemented.

Includes:

```text
MMIO
AXI
DMA
drivers
Python C extensions
FPGA runtime integration
```

---

## 13. Known Limitations

Neither benchmark project currently includes:

- synthesis,
- place and route,
- deployed FPGA bitstream,
- hardware-in-the-loop benchmark execution,
- measured FPGA clock frequency,
- measured accelerator area,
- measured accelerator power,
- measured end-to-end hardware speedup.

Some VM environments also expose PMU limitations. These are preserved in the logs rather than silently replaced with guessed values.

---

## 14. Earlier Coursework

The repository also contains:

```text
hw1/
hw2/
```

These are earlier coursework directories and are not part of the two final benchmark submissions described above.

---

## 15. Summary

The repository demonstrates a full software-to-hardware performance-engineering workflow on two substantially different Python workloads.

### Raytrace

```text
75.76% measured software improvement
~4.12× speedup
Q16.16 intersection accelerator
18/18 RTL checks passed
```

### Pyflate

```text
36.93% measured VM software improvement
1.586× speedup
canonical Huffman streaming accelerator
22/22 RTL checks passed
```

The software gains are measured. The RTL is simulated. The hardware system-level speedups remain estimates until real integration, synthesis, and hardware-in-the-loop measurement are performed.
