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

## VM Audit — 2026-09-21 (DONE via local QEMU/TCG)

Instead of the CS-lab VM (blocked by password reset over Yom Kippur),
we booted an equivalent Ubuntu 22.04 Jammy image (`jammy-server-cloudimg-amd64.img`
from cloud-images.ubuntu.com — the SAME image the course provides) in
local QEMU on Windows and ran the perf profiling there.

- [x] `profiling/perf_stat_baseline.txt`, `profiling/perf_stat_final.txt`
      generated with `perf stat -r 3 -e ...` under `python3-dbg` 3.10.12
      and `pyperformance` 1.14.0.
- [x] `profiling/perf_report_baseline.txt` (6 MB),
      `profiling/perf_report_final.txt` (5 MB) generated with
      `perf record -F 999 -g` + `perf report --stdio`.
- [x] `results/original_official.txt` and `results/final_official.txt`
      updated with both the VM official numbers (elapsed +
      software counters) and the Windows cross-check numbers.
- [x] Hardware counters (cycles/instructions/branches/branch-misses/
      cache-refs/cache-misses) show `<not supported>` — explicitly
      documented in the report and in `docs/03_profiling.md` as a TCG
      limit, mirroring the raytrace team's own note about WHPX
      (`Project/RUN_JAMMY_LOCAL.md`) and the CS-lab VM's PMU issue.

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

### VM official (Ubuntu 22.04 Jammy inside local QEMU, TCG)

| Metric | Value | Source |
|---|---:|---|
| Original elapsed | 1257.09 ± 158 s | `results/original_official.txt` |
| Final elapsed | 740.39 ± 10 s | `results/final_official.txt` |
| Improvement | **41.10%** | derived |
| Speedup | 1.70x | derived |
| task-clock original | 1,079,180 msec | `profiling/perf_stat_baseline.txt` |
| task-clock final | 726,769 msec | `profiling/perf_stat_final.txt` |
| Hardware counters | `<not supported>` (TCG) | docs/03_profiling.md |
| perf_report_baseline top | `_PyEval_EvalFrameDefault` 20.79% | `profiling/perf_report_baseline.txt` |
| perf_report_final top | `_PyEval_EvalFrameDefault` 20.34% | `profiling/perf_report_final.txt` |

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
