# subPyflate Project Plan

**Benchmark:** pyflate (pyperformance)
**Role:** Benchmark #2 for the HWSW project (companion to `Project/subRay/`).
**Source of truth:** Markdown files under `Project/subPyflate/docs/`.
**Evidence policy:**
- MEASURED SOFTWARE, SIMULATED RTL, ESTIMATED HARDWARE, and PROPOSED SYSTEM INTEGRATION are always kept separated.
- Numbers to be filled in on the VM are marked `TO BE COLLECTED IN VM`.

## 1. Requirements Checklist

Legend: `[ ]` not started · `[~]` in progress · `[x]` done.

- [x] R01 — Preserve original pyflate benchmark source untouched.
- [x] R02 — Understand pyflate (algorithm, data structures, entry point, workload).
- [x] R03 — Understand pyperformance and how it runs pyflate.
- [ ] R04 — Establish official baseline (VM).
- [ ] R05 — Profile with perf (record/report/stat) (VM).
- [ ] R06 — Generate py-spy flame graph (VM).
- [x] R07 — Bottleneck analysis (from code inspection and known hotspots).
- [x] R08 — Software optimization Attempt 1 (`find_next_symbol` lookup table).
- [x] R09 — Software optimization Attempt 2 (`move_to_front`, `bwt_transform`, small opts).
- [x] R10 — Software optimization Attempt 3 (attribute hoisting + local-ref helpers).
- [x] R11 — Select final software (`optimized/final/` mirrors best correct attempt).
- [x] R12 — Correctness verification scripts (MD5 identity vs original).
- [ ] R13 — Official before/after measurement (VM, `perf stat` + pyperformance).
- [ ] R14 — Before/after profiling comparison (VM).
- [x] R15 — Hardware accelerator candidate selection (Canonical Huffman decoder).
- [x] R16 — RTL implementation (SystemVerilog).
- [x] R17 — RTL testbenches with reference model.
- [ ] R18 — RTL simulation logs (ModelSim/Icarus/Verilator) — run in VM.
- [x] R19 — HW/SW interface and hardware-performance estimate.
- [x] R20 — Report, README, prompts.

## 2. Directory Layout

```
Project/subPyflate/
├── docs/                  <- step-by-step documentation (this plan and 01..14)
├── original/bm_pyflate/   <- preserved pyperformance pyflate source
├── optimized/
│   ├── attempt1/          <- lookup-table Huffman decode
│   ├── attempt2/          <- MTF / BWT / RLE / int2byte micro-opts
│   ├── attempt3/          <- attribute hoisting + local-ref helpers
│   └── final/             <- selected implementation (default: attempt3)
├── profiling/             <- perf.data / perf reports / flame graphs (VM output)
├── results/               <- baseline + attempt correctness + official comparison
├── reports/               <- consolidated report_pyflate.md and comparison files
├── scripts/               <- runnable orchestrator + per-target scripts
├── hw/
│   ├── rtl/               <- SystemVerilog RTL
│   ├── tb/                <- SystemVerilog testbenches
│   └── results/           <- simulation logs
├── prompts/               <- prompts.md (record of AI prompts used)
└── logs/                  <- environment and command capture from VM
```

## 3. Workflow Order

1. Understand pyflate source (docs/01).
2. Establish baseline in VM (scripts/run_baseline.sh -> results/baseline/, reports/baseline_results.txt).
3. Profile in VM (scripts/run_profile.sh, perf record/report/stat, py-spy).
4. Bottleneck analysis (docs/04).
5. Optimization attempts (optimized/attempt1..3, correctness checks).
6. Select final (docs/06).
7. Official before/after (scripts/script_pyflate.sh compare).
8. Before/after profiling (docs/07).
9. Consistency audit (docs/08).
10. Hardware candidate + architecture + RTL + testbenches + HW/SW interface + performance estimate (docs/09..13).
11. Final report + audit (docs/14, reports/).

## 4. Rules

- Never modify anything in `Project/subRay/`.
- Never modify anything in `Project/subPyflate/original/`.
- Never invent measured numbers. Placeholders are labeled `TO BE COLLECTED IN VM`.
- Every optimization attempt is checked for correctness (MD5 of decompressed output
  matches the reference `afa004a630fe072901b1d9628b960974`).
- Every prompt actually used is recorded in `Project/subPyflate/prompts/prompts.md`.
