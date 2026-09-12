# Nbody Optimization and Accelerator Project

This folder contains the complete Nbody software optimization, profiling, hardware proposal, RTL implementation, simulation, and reporting artifacts.

## Project Layout

- `software/`: pure-Python optimization variants and correctness tests.
- `hardware/`: original accelerator proposal, corrected accelerator, and testbenches.
- `scripts/`: benchmark and perf/FlameGraph automation.
- `results/`: pyperformance data, perf captures, reports, flamegraphs, and the final report.
- `docs/`: project log, profiling instructions, accelerator proposal, and presentation notes.

Start with:

- `docs/nbody_project.md` for the full project history and measured-versus-proposed distinction.
- `docs/nbody_presentation_notes.md` for the final slide plan, speaker notes, and technical Q&A.
- `results/report_nbody.txt` for the final report.
- `results/optimization_comparison.txt` for the measured software timing table.

## Verification Boundary

The Python variants were executed, correctness-tested, and benchmarked. The corrected SystemVerilog accelerator was functionally verified in ModelSim as a separate implementation of the body-pair hotspot.

The accelerator was not synthesized and was not connected to Python. The MMIO/FIFO/DMA interface is a proposal, and no end-to-end hardware-accelerated runtime was measured. Hardware performance scenarios are estimates only.

## Commands

Run software correctness checks from the repository root:

```bash
python3 subNbody/software/test_v1_correctness.py
python3 subNbody/software/test_v2_correctness.py
python3 subNbody/software/test_v3_correctness.py
python3 subNbody/software/test_v4_correctness.py
```

V1-V4 are expected to report `CORRECTNESS_CHECK=PASS`. The full 20,000-step combined variant can be reproduced separately:

```bash
python3 subNbody/software/test_optimized_correctness.py
```

It is expected to report `CORRECTNESS_CHECK=FAIL` at the configured `1e-12` threshold because its recorded maximum position difference is `7.775e-12`. This limitation is documented in the final report; the combined variant was not selected as the best software result.

Run all staged benchmarks in the configured Ubuntu/pyperformance environment:

```bash
bash subNbody/scripts/test_nbody_optimizations.sh
```

Profile the original and best measured V1 implementation at 499 Hz:

```bash
bash subNbody/scripts/profile_nbody_best.sh
```

Profile the same two implementations with the requested 999 Hz project-PDF-compatible and DWARF methods, while preserving all current profile artifacts:

```bash
bash subNbody/scripts/profile_nbody_999_compare.sh
```

The script creates the standard `-F 999 -g` files and the DWARF `--call-graph dwarf` files under `/root/homewroksbothsofthard/project_results/nbody` without overwriting any existing file.

Compile and run the comprehensive RTL testbench from the repository root:

```powershell
vlib.exe work
vlog.exe -sv subNbody\hardware\nbody_accel_v2.sv subNbody\hardware\tb_nbody_accel.sv
vsim.exe -c -do "run -all; quit -f" work.tb_nbody_accel
```

Expected simulation verdict:

```text
NBODY_ACCEL_TEST=PASS transfers=12 latency=5 throughput=1/cycle
```
