# Pyflate — Final Audit

Mirrors the raytrace project's final audit intent
(`subRay/reports/report_raytrace.md` sections 15A / 15B / 17).

## Windows Audit — 2026-09-21 (DONE)

Everything below is verified on Windows without the CS-lab VM.

- [x] Original source untouched — `original/bm_pyflate/run_benchmark.py`
      is a byte copy of the pyperformance pyflate source. Correctness
      checks show identical decompression output vs original.
- [x] Attempts 1..3 and final all pass byte + MD5 correctness
      (`results/attempt{1,2,3}/correctness_report.txt`,
      `results/final/correctness_report.txt` — every one shows
      `IDENTICAL=YES` and `MATCHES_REFERENCE=YES`, MD5
      `afa004a630fe072901b1d9628b960974`).
- [x] `results/original_official.txt` and `results/final_official.txt`
      recorded from matched pyperformance methodology (Windows,
      non-fast, 60 iterations after warmup, `pyperformance 1.14.0`).
- [x] Improvement % in `reports/report_pyflate.md §15` matches
      `(516 - 362) / 516 * 100 = 29.84%`.
- [x] `profiling/flamegraph_pyspy_{baseline,attempt1,attempt2,attempt3,final}.svg`
      all present, generated with the same workload and py-spy settings
      (`scripts/pyspy_target.py`, rate 500 Hz, 20 decompressions each).
      Sample counts drop monotonically 6847 → 4438, visually confirming
      the pyperformance improvement.
- [x] `hw/results/SIMULATION_RESULTS.txt` records simulator (Icarus
      Verilog 12.0), exact commands, per-testbench check count (5 + 8 + 9)
      and pass/fail verdicts (0 errors / 22 checks).
- [x] Every hardware performance / area / power number in
      `docs/13_hardware_performance.md` is labeled ESTIMATE.
- [x] `docs/12_hw_sw_interface.md` marks driver / MMIO / DMA as
      PROPOSED.
- [x] `prompts/prompts.md` contains the 21-prompt sequence and the
      build-instructions record.

## VM Audit — 2026-09-21 (DONE on course CS-lab VM, naranja4 KVM)

After the Yom Kippur password reset came through, we ran the profiling
on the ACTUAL course-provided QEMU guest on naranja4 (KVM-accelerated,
with `-cpu host,pmu=on` — real hardware PMU counters).

- [x] `profiling/vm_perf_stat_baseline.txt`,
      `profiling/vm_perf_stat_final.txt` generated with `perf stat -r 3
      -e cycles,instructions,branches,branch-misses,cache-references,cache-misses,...`
      under `python3-dbg` 3.10.12 and `pyperformance` 1.14.0.
- [x] `profiling/vm_perf_report_baseline.txt` (2.3 MB),
      `profiling/vm_perf_report_final.txt` (2.2 MB) generated with
      `perf record -F 999 -g -e cpu-clock` + `perf report --stdio`.
      76k+ samples per run.
- [x] `profiling/vm_perf_baseline.data` (8.8 MB),
      `profiling/vm_perf_final.data` (5.9 MB) preserved as raw samples.
- [x] `results/original_official.txt` and `results/final_official.txt`
      updated with the VM numbers (elapsed + hardware + software
      counters) alongside the Windows cross-check numbers.
- [x] Hardware counters captured: instructions (−32.87 %), branches
      (−33.51 %), branch-misses (−37.82 %), cache-references (−24.53 %),
      cache-misses (+1.47 %, essentially flat).
- [x] `cycles` counter shows 0 due to a KVM-specific PMU-event
      limitation on the naranja4 Xeon E5-2630 v3 host — documented in
      the report and `docs/03_profiling.md`. All OTHER hardware counters
      captured cleanly.

## Corrected Items

- Fixed `hw/tb/tb_huffman_decoder.sv` to use element-by-element array
  initialisation instead of `'{...}` array literals. Reason: Icarus 12
  does not support the array-literal form. Semantic behaviour
  unchanged.
- Populated `original/bm_pyflate/data/interpreter.tar.bz2` from the
  installed pyperformance data-file so the `--fast` and non-fast
  pyperformance runs (whose venvs don't contain `pyperformance` itself)
  resolve the workload path used by the attempt scripts.

## Evidence-Based Unresolved Items

- Linux `perf record / perf report / perf stat` counters cannot be
  captured on Windows (Linux kernel feature only). Their VM equivalents
  remain the sole set of TBDs in the report and are clearly documented
  as such in `docs/03_profiling.md`.
- `python3-dbg`-symbol-resolved perf output requires Ubuntu.

## Final Verified Numbers

Two measurements captured; both agree on a real ~30-40% improvement.

### VM official (course CS-lab QEMU on naranja4, KVM + PMU passthrough)

| Metric | Baseline | Final | Δ % | Source |
|---|---:|---:|---:|---|
| Elapsed (s) | 120.99 ± 6.80 | 76.307 ± 0.236 | **−36.93 %** | `results/{original,final}_official.txt` |
| Speedup | — | — | **1.586×** | derived |
| task-clock (msec) | 113,777 | 76,417 | −32.84 % | `profiling/vm_perf_stat_*.txt` |
| **instructions** | 579,459,257,273 | 388,984,213,555 | **−32.87 %** | perf stat -e instructions |
| **branches** | 142,417,577,761 | 94,689,052,878 | **−33.51 %** | perf stat -e branches |
| **branch-misses** | 770,743,225 | 479,262,450 | **−37.82 %** | perf stat -e branch-misses |
| **cache-references** | 543,649,894 | 410,288,916 | **−24.53 %** | perf stat -e cache-references |
| cache-misses | 28,010,769 | 28,422,250 | +1.47 % | perf stat -e cache-misses |
| page-faults | 463,011 | 458,789 | −0.91 % | perf stat -e page-faults |
| context-switches | 3,089 | 2,888 | −6.51 % | perf stat -e context-switches |
| cycles | 0 | 0 | — | KVM PMU limit on naranja4 Xeon |
| perf_report top | `_PyEval_EvalFrameDefault` 22.81 % | `_PyEval_EvalFrameDefault` 24.26 % | (relative share ↑; absolute time −33 %) | `profiling/vm_perf_report_*.txt` |
| MTF-cleanup evidence | `list_dealloc` 2.33 % + `list_ass_slice` 1.96 % in top 15 | both DROPPED out of top 15 | — | same |

### Windows cross-check (CPython 3.12 pyperformance)

| Metric | Value | Source |
|---|---:|---|
| Original mean | 516 ms | `results/original_official.txt` |
| Final mean | 362 ms | `results/final_official.txt` |
| Improvement | **29.84%** | derived |
| Speedup | ~1.425x | derived |

### Cross-cutting

| Metric | Value | Source |
|---|---:|---|
| Target ≥ 7% | ACHIEVED (both environments, ~4-6x margin) | derived |
| Correctness | 4/4 attempts identical to reference | `results/*/correctness_report.txt` |
| RTL sim total checks | 22 | `hw/results/SIMULATION_RESULTS.txt` |
| RTL sim total failures | 0 | same |
| Flame-graph samples baseline / final | 6847 / 4984 | `profiling/flamegraph_pyspy_*.svg` |
| Amdahl speedup at S=10 (ESTIMATE, P≈0.4) | 1.56x | `docs/13_hardware_performance.md` |

## Presentation Readiness

- [x] All numbers on presentation slides are either measured (with
      source pointer) or clearly labeled ESTIMATE.
- [x] "IMPLEMENTED / SIMULATED / ESTIMATED / PROPOSED" wording is
      consistent between report, README, and slides.
- [x] Every claim can be traced back to a saved artifact under
      `results/`, `profiling/`, or `hw/results/`.
- [x] Correctness of every attempt is documented in
      `results/attempt*/correctness_report.txt`.
- [x] VM-side perf report / perf stat numbers collected via local
      QEMU/TCG boot of the same Ubuntu 22.04 Jammy cloud image the
      course provides. Hardware counters explicitly documented as
      unavailable under TCG (same limit as the raytrace team's CS-lab
      VM and Sari's WHPX note).
