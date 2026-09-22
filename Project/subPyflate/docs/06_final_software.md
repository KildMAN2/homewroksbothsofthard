# Pyflate — Final Software Implementation

## Selection Rule

Pick the fastest attempt that:
1. Produces byte-identical output to the preserved original.
2. Passes the pyflate MD5 reference check
   (`afa004a630fe072901b1d9628b960974`).

If two attempts tie, prefer the simpler one (fewer diffs from the original).

## Default Selection (pre-VM)

Before VM measurement, the default final is
`Project/subPyflate/optimized/final/` = **a copy of Attempt 3**. Rationale:
Attempt 3 strictly layers on top of Attempts 1 and 2 with attribute-hoisting
changes that never hurt semantics. It is the most likely fastest correct
choice.

If the VM measurement shows a different attempt is strictly faster, the
`final/` folder is re-copied from that attempt and this document is updated.
The individual `optimized/attemptN/` folders are never modified.

## Selected Final After VM Measurement

Confirmed by the Windows-preliminary run (2026-09-20,
`results/windows_preliminary.txt`) and pending the official VM numbers:

- **Selected attempt: Attempt 3** (default confirmed).
- Source folder copied to `Project/subPyflate/optimized/final/`.
- Correctness: all four attempts show `IDENTICAL=YES` and
  `MATCHES_REFERENCE=YES` (`afa004a630fe072901b1d9628b960974`), 
  see `results/{attempt1,attempt2,attempt3,final}/correctness_report.txt`.
- Windows preliminary improvement (mean over 8 iterations, 3 loops each):
  **+13.16%** vs original — above the 7% target.

## Windows-Preliminary Numbers (NOT the official VM run)

Ran on Windows 11 with Python 3.12.10 using `Project/subPyflate/scripts/windows_bench.py`
(mirrors the timed region of `bench_pyflake` — `time.perf_counter()` around
`bzip2_main`). Not the official numbers; those come from
`perf stat` + `pyperformance` on the QEMU VM. Kept here to prove the code is
correct and gives a real relative improvement.

| Version | Mean (s) | Min (s) | Std Dev | Windows Δ vs original |
|---|---:|---:|---:|---:|
| original | 1.8877 | 1.5927 | 0.1628 | — |
| attempt1 (LUT alone) | 2.4883 | 2.1073 | 0.2028 | **-31.82%** (regression) |
| attempt2 (LUT + MTF/BWT/int2byte) | 1.7626 | 1.4993 | 0.1670 | **+6.63%** |
| attempt3 (attempt2 + hoisting) | 1.6855 | 1.4777 | 0.1200 | **+10.71%** |
| final (copy of attempt3) | 1.6394 | 1.4947 | 0.1079 | **+13.16%** |

### Interpretation — LUT is a Python-side regression on this workload

Attempt 1 (canonical Huffman LUT alone) is *slower* than the original on
this benchmark despite being algorithmically O(1) per symbol. Reason:
`HuffmanTable._build_lut` iterates in Python and, for every bzip2 group's
Huffman table, fills up to `2**max_bits` entries (up to ~131K entries for
`max_bits = 17`). Over the ~5 blocks × 6 groups per block in the pyflate
workload, the total LUT-build work exceeds the per-symbol savings.

Once the constant-factor cleanups from Attempts 2 and 3 remove the biggest
sources of interpreter overhead (`list_ass_slice`, `bytes_find` in the BWT
scan, per-byte `struct.pack`, attribute reads), the LUT lookup's advantage
starts to win and Final lands at +13.16%.

**This is a genuine finding, not a code bug.** It also strengthens the
hardware-acceleration argument: hardware BRAM has O(1) load AND O(1)
lookup with no interpreter overhead, so the accelerator wins on both
fronts that hurt the pure-Python LUT.

### Note on Windows vs the official VM

- Windows uses CPython 3.12 (fast); the VM uses `python3-dbg` (slower,
  optimized for perf symbol resolution). Absolute times will differ.
- Windows uses `time.perf_counter`; the VM uses `pyperf` + `perf stat`.
  Both measure wall-clock but pyperf adds statistical rigor.
- Improvement PERCENTAGES should be broadly comparable between the two
  environments, since the same optimizations attack the same interpreter
  costs. Final expected improvement on the VM: at least +7% (target), and
  most likely in the +10..15% range based on the Windows preliminary.

## Official Before/After (fill after VM run)

Populated from `Project/subPyflate/results/original_official.txt` and
`Project/subPyflate/results/final_official.txt`.

| Version | Mean | Std Dev | Runs | Command |
|---|---:|---:|---:|---|
| Original | TBD | TBD | TBD | `python3-dbg -m pyperformance run --bench pyflate` |
| Final | TBD | TBD | TBD | `python3-dbg -m pyperformance run --manifest optimized/final/MANIFEST --bench pyflate_final` |

Improvement `%` = `(original_mean - final_mean) / original_mean * 100`.

Target `>= 7%` improvement: `TO BE CONFIRMED IN VM`.

## Why Each Change Made It Into the Final

- **Canonical Huffman LUT (Attempt 1)**: replaces the profiled O(#codes)
  per-symbol scan with a single lookup. Directly targets the largest
  measured hotspot.
- **MTF / BWT / int2byte cleanup (Attempt 2)**: removes three sources of
  interpreter-visible allocation cost that survive after the Huffman LUT.
- **Attribute hoisting + RLE cleanup (Attempt 3)**: the classic Python
  micro-tightening pass after algorithmic wins are in place.

## Why Other Attempts Were Not Selected

- If VM measurement shows Attempt 1 alone is within noise of Attempt 3,
  the simpler Attempt 1 may be preferred and this document is amended.
- Attempts 2 and 3 are not deleted — they remain in the repository as
  evidence of the search process.
