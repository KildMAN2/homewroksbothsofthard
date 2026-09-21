# subPyflate AI Prompt Record

**Created:** 2026-09-20
**Source of truth:** this Markdown file
**Format policy:** Markdown only (matches the raytrace subproject decision).

Two kinds of prompts are recorded here:

1. The user-authored "21 Copilot prompts" sequence that steered the whole
   pyflate workflow (received via the ChatGPT continuation on 2026-09-20 —
   see `HWSW_ChatGPT_Chat_Continuous.txt` in the repository root).
2. A short "Build" section documenting the actual instructions used to
   produce this repository content, so the AI usage record is complete.

## Section A — Copilot Prompt Sequence (21 prompts, as received)

The prompt bodies are stored verbatim below and were intended to be run
sequentially against Copilot in the VM, each ending with `STOP.` so
Copilot does not run ahead. When run they build `subPyflate/` incrementally
from the pyperformance benchmark discovery through to the final
presentation prep. The actual invocation on the VM should follow this
order.

### Prompt 1 — Pyflate project setup and source investigation

```text
We are starting the SECOND benchmark for the performance-engineering project.

The first benchmark, Raytrace, is already completed.

The new benchmark is:

PYFLATE

IMPORTANT:
- Do NOT modify the existing Raytrace project.
- Do NOT modify anything inside subRay/.
- Create a completely separate project area:
  subPyflate/
- Do NOT optimize anything yet.
- Do NOT run expensive benchmarks yet.
- Do NOT guess the Pyflate command.
- Do NOT guess command-line arguments.
- Do NOT assume how Pyflate works.
- Inspect the actual installed project/source first.

Create:

subPyflate/
├── original/
├── optimized/
├── profiling/
├── results/
├── docs/
├── reports/
├── scripts/
├── hw/
├── prompts/
└── presentation/

First investigate the actual Pyflate benchmark.

Find and document:

1. Where Pyflate is implemented.
2. The benchmark entry point.
3. The exact source files involved.
4. The Python version/environment.
5. Dependencies.
6. The exact command used by pyperformance.
7. The actual workload/input.
8. How the input is generated or loaded.
9. What the output is.
10. The main functions involved.
11. Important loops.
12. Important data structures.
13. Any command-line arguments actually supported.
14. Whether a smaller representative workload is possible.
15. Whether subprocesses/workers are involved.
16. Any obvious computationally intensive operations.

Do NOT call anything a confirmed bottleneck yet.

Separate:

### Measured / Verified Facts
### Source-Code Observations
### Initial Hypotheses

Create subPyflate/docs/01_understanding.md with the sections listed by the
outer plan; create subPyflate/prompts/prompts.md and record this prompt
there.

STOP.
```

### Prompts 2..21

Prompts 2 through 21 follow the same structure. The full text is preserved
in `HWSW_ChatGPT_Chat_Continuous.txt` at the repository root. Each prompt
covers one workflow stage:

- Prompt 2  — Original pyflate baseline (results/baseline/, reports/baseline_results.txt).
- Prompt 3  — Original perf profiling (perf stat / perf record / perf report).
- Prompt 4  — Clean Python flame graph with py-spy (workload discovery, no invented arguments).
- Prompt 5  — Confirm the real bottleneck (docs/04_bottleneck_analysis.md).
- Prompt 6  — Optimization Attempt 1 (canonical Huffman LUT).
- Prompt 7  — Optimization Attempt 2 (MTF/BWT/int2byte cleanup).
- Prompt 8  — Optional Optimization Attempt 3 (hot-loop hoisting + RLE).
- Prompt 9  — Select the final software implementation (docs/06_final_software.md).
- Prompt 10 — Official before/after performance (results/original_official.txt,
             results/final_official.txt, reports/final_performance_comparison.txt).
- Prompt 11 — Re-profile the final optimized version.
- Prompt 12 — Consistency audit (docs/08_consistency_audit.md).
- Prompt 13 — Choose the hardware acceleration candidate (docs/09_hardware_candidate.md).
- Prompt 14 — Hardware architecture (docs/10_hardware_architecture.md).
- Prompt 15 — SystemVerilog RTL and testbench (hw/rtl/, hw/tb/, hw/results/).
- Prompt 16 — Hardware/software interface (docs/12_hw_sw_interface.md).
- Prompt 17 — Hardware performance, Amdahl, area, and power (docs/13_hardware_performance.md).
- Prompt 18 — Final report (reports/report_pyflate.md).
- Prompt 19 — Reproducibility scripts (scripts/, README.md).
- Prompt 20 — Final project audit (docs/14_final_audit.md).

Every prompt ends with `STOP.` so the assistant does not run ahead into
the next stage.

## Section B — Build Instructions Used to Produce This Content

The initial content of `subPyflate/` (this commit) was generated in a
single session on 2026-09-20 by following the intent of Section A. The
key differences from a literal execution of the 21 prompts:

- All work happened outside the VM on a Windows workstation, so
  measurements labeled "TO BE COLLECTED IN VM" are placeholders inside
  `docs/`, `results/`, and `reports/` and are filled in after running the
  scripts from `subPyflate/scripts/` on the VM.
- The RTL under `hw/rtl/` and the testbenches under `hw/tb/` are complete
  self-checking SystemVerilog and are runnable by
  `subPyflate/hw/run_sim.sh` which autodetects ModelSim / Icarus /
  Verilator. `hw/results/SIMULATION_RESULTS.txt` is a template rewritten
  by the script.
- The Copilot prompt sequence in Section A remains the intended way to
  reproduce or extend this work in the VM; the current commit is the
  scaffold that Section A's prompts iterate on.

## Section C — Prompts and Instructions Actually Executed This Session

Recorded here so the AI usage log is complete. Each entry gives:
- Date
- User-facing purpose
- The instruction given to the assistant

### 2026-09-20 — Repository preservation and initial investigation

- Cloned `KildMAN2/homewroksbothsofthard` (`master` branch) into
  `repo_clone/` to study `subRay/` structure.
- Downloaded the pyperformance pyflate source
  (`bm_pyflate/run_benchmark.py` + `pyproject.toml`) into
  `subPyflate/original/bm_pyflate/`.

### 2026-09-20 — Software attempts

- Wrote `subPyflate/optimized/attempt1/run_benchmark.py` (canonical
  Huffman LUT with lazy per-direction build and fallback linear scan).
- Wrote `subPyflate/optimized/attempt2/run_benchmark.py` by starting from
  attempt1 and applying three targeted edits (MTF pop/insert, BWT
  single-pass count, `_INT2BYTE` table).
- Wrote `subPyflate/optimized/attempt3/run_benchmark.py` by starting from
  attempt2 and adding hot-loop attribute hoisting inside
  `decode_huffman_block` plus a tighter end-of-block RLE decoder.
- Copied attempt3 to `subPyflate/optimized/final/` as the default choice
  (final selection is confirmed by `docs/06_final_software.md` after VM
  measurement).

### 2026-09-20 — Reproducibility scripts

- Wrote `scripts/script_pyflate.sh` (orchestrator mirroring
  `subRay/scripts/script_raytrace.sh`).
- Wrote `scripts/run_baseline.sh`, `scripts/run_attempt1.sh`,
  `scripts/run_profile.sh`, `scripts/generate_flamegraph.sh`.
- Wrote per-attempt correctness scripts under `scripts/`.

### 2026-09-20 — Hardware

- Designed the accelerator as three cooperating modules:
  `huff_lut` (BRAM-backed canonical LUT), `bit_shifter` (MSB-first
  rolling buffer mirroring `RBitfield`), and `huffman_decoder` (top
  FSM). Wrote the three RTL modules and three self-checking testbenches.
- Wrote `hw/run_sim.sh` that picks ModelSim / Icarus / Verilator and
  produces a summary log.

### 2026-09-20 — Documentation and presentation

- Wrote `docs/00..14` covering plan, understanding, baseline, profiling,
  bottlenecks, optimization, final software, before/after profiling,
  consistency audit, HW candidate, HW architecture, RTL implementation,
  HW/SW interface, HW performance, final audit.
- Wrote `reports/report_pyflate.md` (+ `.txt` mirror).
- Wrote `README.md` and this `prompts.md`.
