# subRay HWSW Project Plan

**Project:** Benchmark Optimization, Analysis, and Hardware Acceleration  
**Benchmark:** `<BENCHMARK>` (identifier not yet supplied)  
**Root working directory:** `subRay/`  
**Created:** 2026-09-13  
**Current phase:** Planning only; no benchmark code has been inspected or modified.

## Status Legend

- `[ ]` Not started
- `[~]` In progress
- `[x]` Completed

## Global Workflow

Every meaningful task will follow this sequence:

1. Update the relevant Markdown document before acting.
2. Explain the intended work, command, expected evidence, and decision criteria.
3. Perform the documented work.
4. Preserve raw outputs under `profiling/`, `results/`, `logs/`, or `hw/results/` as appropriate.
5. Update the Markdown document with the actual outcome, warnings, errors, and decisions.

DOCX generation is no longer required (user decision, 2026-09-13). Markdown files are the sole deliverable format and source of truth. Failed experiments, warnings, and errors will be retained. Measurements will never be invented. Hypotheses and estimates will be labeled explicitly.

## Scientific Controls

- Preserve the original benchmark unchanged under `subRay/original/`.
- Do not modify benchmark code before baseline profiling unless a documented change is strictly required to run it.
- Put all modified implementations under `subRay/optimized/`.
- Verify correctness before accepting an optimization.
- Compare every optimized candidate directly against the original baseline.
- Benchmark before claiming an improvement.
- Preserve failed or regressed optimization attempts and their raw evidence.
- Distinguish measured facts, observations, hypotheses, and estimates.
- Report hardware performance only when measured.
- Label all projected hardware values as **ESTIMATE**.

## Required Directory Layout

```text
subRay/
|-- docs/
|-- original/
|-- optimized/
|-- scripts/
|-- profiling/
|-- reports/
|-- results/
|-- logs/
|-- hw/
|   |-- rtl/
|   |-- tb/
|   `-- results/
|-- presentation/
`-- prompts/
```

The working directories will be created when execution begins. This planning step creates only the required plan and prompt documentation.

## Requirements Checklist

| Status | ID | Requirement | Planned evidence |
|---|---:|---|---|
| `[x]` | 1 | Understand benchmark | Completed in `docs/01_benchmark_understanding.md` with exact VM source identification and checksums. |
| `[x]` | 2 | Understand pyperformance | Completed in `docs/02_pyperformance.md` and the baseline artifacts: pyperformance `1.14.0`, Python `3.10.12`, and `python3-dbg` availability are now verified. |
| `[x]` | 3 | Obtain baseline performance | Completed in `docs/03_baseline.md`, `logs/03_baseline_run.log`, and `results/baseline/` with preserved raw output and baseline summary. |
| `[x]` | 4 | Generate profiling data | Completed via the successful baseline `perf record` run; reuse and report-generation attempts are documented in `docs/04_perf_profiling.md`. |
| `[ ]` | 5 | Generate flame graph | Save collapse/render commands, warnings, intermediate data as needed, and baseline flame graph. |
| `[ ]` | 6 | Detect bottlenecks | Analyze measured profiles and record evidence-backed bottlenecks separately from hypotheses. |
| `[ ]` | 7 | Suggest improvements | Propose ranked software changes tied to measured bottlenecks, with correctness risks and expected mechanisms. |
| `[ ]` | 8 | Implement optimizations | Create versioned candidates under `optimized/`; never edit the original benchmark. |
| `[ ]` | 9 | Measure performance improvement | Correctness-check each candidate, benchmark accepted candidates, and preserve regressions and failures. |
| `[ ]` | 10 | Compare original vs optimized | Produce direct original-versus-candidate comparisons with raw data and statistical context. |
| `[ ]` | 11 | Propose hardware acceleration | Select an evidence-backed kernel and document the proposed accelerator boundary and assumptions. |
| `[ ]` | 12 | Implement a logically complete hardware design | Add synthesizable RTL and a self-checking testbench under `hw/rtl/` and `hw/tb/`. |
| `[ ]` | 13 | Explain HW/SW interface | Define data representation, registers or streams, batching, control, synchronization, and error handling. |
| `[ ]` | 14 | Discuss performance/area/power tradeoffs | Separate measured implementation results from explicitly labeled estimates and qualitative tradeoffs. |
| `[ ]` | 15 | Create scripts | Add reproducible setup, correctness, benchmark, profiling, flame graph, RTL, and report-generation scripts. |
| `[ ]` | 16 | Create final benchmark report | Consolidate method, environment, raw evidence, results, limitations, failures, and conclusions. |
| `[ ]` | 17 | Create README | Provide a file map, prerequisites, reproduction commands, selected result, and evidence boundaries. |
| `[ ]` | 18 | Save AI prompts | Maintain `prompts/prompts.md` with important project instructions and prompts. |
| `[ ]` | 19 | Prepare presentation material | Create concise slides or notes covering benchmark, evidence, optimization, RTL, interface, and limitations. |

## Planned Phases

### Phase 0: Controlled setup

- Confirm the benchmark identity represented by `<BENCHMARK>`.
- Create the remaining directory structure.
- Inventory files without changing benchmark code.
- Record tool and environment availability, including pyperformance, perf, FlameGraph tools, pandoc, and RTL tools.

### Phase 1: Benchmark understanding and baseline

- Document the benchmark algorithm and correctness contract.
- Document how pyperformance executes it.
- Establish a reproducible original baseline and save raw results.

### Phase 2: Profiling and bottleneck analysis

- Profile the untouched original implementation.
- Generate a flame graph.
- Identify measured hotspots and formulate testable optimization hypotheses.

### Phase 3: Software optimization

- Implement candidates as separate files or directories.
- Validate correctness before performance testing.
- Compare every candidate with the original baseline.
- Select the best valid measured result, not merely the newest variant.

### Phase 4: Hardware acceleration

- Choose a kernel based on algorithm and profiling evidence.
- Specify numeric formats and the HW/SW contract.
- Implement logically complete RTL and a self-checking testbench.
- Record simulation evidence separately from synthesis or deployed-hardware evidence.

### Phase 5: Final reporting and presentation

- Produce the final report, README, reproducibility scripts, prompt record, and presentation material.
- Audit all claims against raw artifacts.

## Current Decisions and Blockers

- **Decision:** No benchmark code will be inspected or modified during this planning-only step.
- **Decision:** Markdown is the sole deliverable and source of truth; DOCX generation is no longer required (user decision, 2026-09-13).
- **Blocker:** The benchmark placeholder `<BENCHMARK>` has not yet been replaced with a concrete benchmark name or source location.

## Activity Log

### 2026-09-13 - Initial plan creation

**Before action:** Create this project plan with all 19 requirements marked `[ ]` Not started. Record the documentation-first workflow and scientific controls. Do not inspect or modify benchmark code.

**Planned command:** Check whether `pandoc` is available for optional DOCX generation.

**Actual outcome:** `pandoc` was not available (`pandoc command not found`), so no DOCX was generated. The raw check output is preserved in `subRay/logs/00_pandoc_check.txt`. DOCX generation was subsequently dropped from the workflow on user request (2026-09-13); Markdown is now the sole deliverable. No benchmark code was inspected or modified.
