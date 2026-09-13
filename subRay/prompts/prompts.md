# subRay AI Prompt Record

**Created:** 2026-09-13  
**Source of truth:** This Markdown file  
**DOCX policy:** DOCX generation is no longer required (user decision, 2026-09-13). Markdown files are the sole deliverable format.

## Prompt 001 - Project Initialization and Documentation Rules

**Date:** 2026-09-13  
**Purpose:** Establish the complete documentation-first workflow for one HWSW benchmark project.

### Important instructions received

- Work on one benchmark for the HWSW project: Benchmark Optimization, Analysis, and Hardware Acceleration.
- Use `subRay/` as the root working directory.
- Treat `<BENCHMARK>` as a placeholder until the concrete benchmark identity is supplied.
- Document every meaningful task before performing it, preserve raw output, then update the documentation with the actual outcome.
- Keep Markdown as the source of truth and generate matching DOCX files with pandoc whenever possible.
- Never modify the original benchmark directly.
- Do not modify benchmark code before profiling unless a documented change is required merely to run it.
- Never invent measurements or claim improvement without benchmarking.
- Preserve failed experiments, warnings, and errors.
- Separate measured facts from hypotheses and explicitly label estimated hardware values as **ESTIMATE**.
- Compare optimized candidates directly against the original baseline.
- Verify correctness before accepting an optimization.
- Complete and document all 19 project requirements covering benchmark understanding, pyperformance, baseline measurement, profiling, flame graphs, bottleneck analysis, optimization, hardware design, HW/SW interfacing, tradeoffs, scripts, reports, README, prompts, and presentation material.
- First create `subRay/docs/00_project_plan.md` and `subRay/docs/00_project_plan.docx`, with all requirements represented by `[ ]`, `[~]`, or `[x]` status markers.
- Stop after creating and showing the plan. Do not begin benchmark inspection or modification.

### Action planned before execution

1. Create `subRay/docs/00_project_plan.md` with all 19 requirements marked `[ ]` Not started.
2. Create this prompt record.
3. Check whether pandoc is available.
4. If available, generate both requested DOCX counterparts. If unavailable or conversion fails, record that fact in the Markdown files.
5. Stop without inspecting or modifying benchmark code.

### Actual outcome

- `subRay/docs/00_project_plan.md` was created with all 19 requirements marked `[ ]` Not started.
- `pandoc` was not available (`pandoc command not found`), so neither DOCX counterpart could be generated.
- The raw tool check is preserved in `subRay/logs/00_pandoc_check.txt`.
- No benchmark code was inspected or modified.

## Prompt 002 - Benchmark Understanding

**Date:** 2026-09-13  
**Purpose:** Identify and document the exact pyperformance benchmark implementation without modifying or executing it.

### Important instructions received

- Create `subRay/docs/01_benchmark_understanding.md` before analysis and later create its DOCX counterpart.
- Locate the exact implementation executed by pyperformance.
- Document the source file, benchmark name, entry point, purpose, workload, libraries, modules, dependencies, functions, classes, data structures, algorithms, loops, mathematics, memory behavior, call structure, inputs, outputs, invocation path, and exact timed region.
- Include a simple execution-flow diagram.
- List potential bottlenecks only as unprofiled hypotheses.
- Copy untouched relevant sources to `subRay/original/` and calculate SHA256 checksums.
- Do not modify benchmark code.
- Stop after benchmark understanding is complete.

### Action planned before execution

Create the Markdown source first; perform read-only registration and source tracing; preserve and checksum the exact originals; update the document with evidence; attempt DOCX generation; then stop without executing or modifying the benchmark.

### Actual outcome

Completed in `subRay/docs/01_benchmark_understanding.md`. The VM benchmark was resolved as `raytrace`; its untouched source and metadata were preserved under `subRay/original/bm_raytrace/` with matching SHA256 checksums. No benchmark workload was executed and no source was modified.

DOCX generation was attempted after completing the Markdown but failed because `pandoc` is not installed. The error is preserved in `subRay/logs/01_pandoc_check.txt`.

## Prompt 003 - Search Inside the VM

**Date:** 2026-09-13  
**Purpose:** Clarify where benchmark discovery must occur.

### Important instruction received

- Search for the active pyperformance benchmark implementation inside the running VM.

### Action planned before execution

Identify the active VM connection, then use short read-only commands inside the VM to resolve the installed pyperformance path, benchmark registration, and exact source. Preserve raw discovery output and do not modify or execute benchmark code.

### Actual outcome

The VM search identified pyperformance `1.14.0`, benchmark name `raytrace`, manifest registration `raytrace     <local>`, and installed source directory `/usr/local/lib/python3.10/dist-packages/pyperformance/data-files/benchmarks/bm_raytrace`.

## Prompt 004 - Reconnect QEMU Before Discovery

**Date:** 2026-09-13  
**Purpose:** Restart and connect to the VM before repeating benchmark understanding.

### Important instruction received

- Connect to QEMU first, then complete the previously specified benchmark-understanding task.

### Action planned before execution

Start the existing Jammy QEMU disk with its serial console and SSH forwarding, confirm guest access, and then continue only the documented read-only discovery work.

### Actual outcome

QEMU booted successfully to Ubuntu 22.04.5. After the user completed login directly in the terminal, read-only benchmark discovery completed. No benchmark workload was executed and no benchmark code was modified.

## Prompt 005 - Markdown Only, No DOCX

**Date:** 2026-09-13  
**Purpose:** Simplify deliverables.

### Important instruction received

- No DOCX is needed; keep Markdown only.

### Action planned before execution

Stop attempting pandoc DOCX generation. Update the documentation policy so Markdown files are the sole source of truth and deliverable, and reframe prior DOCX-generation failures as no longer applicable rather than open limitations.

### Actual outcome

DOCX generation is dropped from the workflow. The originals under `subRay/original/bm_raytrace/` were re-verified after external edits and still match the VM SHA256 hashes exactly (`88ef4d90...` and `b003d38f...`). No benchmark code was modified.

## Prompt 006 - Analyze How pyperformance Executes raytrace

**Date:** 2026-09-13
**Purpose:** Document the pyperformance execution model and measurement vocabulary for `raytrace`.

### Important instructions received

- Create `subRay/docs/02_pyperformance.md` before running experiments.
- Document installed Python version, python3-dbg availability, pyperformance version, exact benchmark identifier, how to list and run the benchmark, and the meaning of loops, values, processes, warmups, repetitions, mean, standard deviation, and stability, plus why multiple measurements are required.
- Save every command executed and raw outputs under `subRay/logs/`.
- Do not optimize. No DOCX needed. Stop after the Markdown is complete.

### Action planned before execution

Create the Markdown source first with the plan and stable concept definitions; gather version/availability/list facts with read-only VM commands; save raw outputs; update the document; then stop.

### Actual outcome

The interactive QEMU serial handle was unavailable this turn. On the user's instruction, the step was completed using only VM output already captured earlier today (`subRay/logs/02_pyperformance_env.txt`). Verified: pyperformance `1.14.0`, benchmark id `raytrace`, interpreter minor `3.10`, `/usr/bin/python3` launcher, and the list/run commands. Recorded as unverified rather than guessed: python3 exact patch version and python3-dbg availability. All measurement concepts were documented. No benchmark run, no optimization, no source change, no DOCX.
