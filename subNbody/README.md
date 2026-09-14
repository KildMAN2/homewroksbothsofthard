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
- `../project_results/nbody/report_original_pdf.txt` and `report_v1_pdf.txt` for the final perf reports.
- `../project_results/nbody/flamegraph_original_pdf.svg` and `flamegraph_v1_pdf.svg` for the final flamegraphs.
- `../project_results/prompt.txt` for the required record of AI prompts used during the workflow.

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

The final profiling method is PDF-style call-graph sampling at 999 Hz:

```bash
perf record -F 999 -g -- python3-dbg -m pyperformance run --bench nbody
perf record -F 999 -g -- python3-dbg -m pyperformance run --bench nbody_v1
```

The authoritative submission artifacts are:

- `project_results/nbody/report_original_pdf.txt`
- `project_results/nbody/report_v1_pdf.txt`
- `project_results/nbody/flamegraph_original_pdf.svg`
- `project_results/nbody/flamegraph_v1_pdf.svg`

The older 499 Hz and earlier 999 Hz files remain historical/development artifacts only. They are not the final profiling evidence. DWARF profiling is also not part of the final method; a prior 999 Hz DWARF experiment exceeded the VM's practical memory limit.

The final PDF-style reports show `list_subscript` decreasing from about `1.62%` to `0.01%` and `PyObject_GetItem` from about `1.53%` to `0.04%`. This supports the conclusion that V1 scalarization reduced repeated Python list-access overhead.

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

This is functional RTL simulation evidence only. There is no implemented HW/SW integration and no measured hardware speedup.
