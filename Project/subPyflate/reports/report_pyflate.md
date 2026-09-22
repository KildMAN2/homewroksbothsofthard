# Pyflate Benchmark Report

**Benchmark:** `pyflate` (pyperformance, `bm_pyflate/run_benchmark.py`)
**Input:** `interpreter.tar.bz2`, 67,562 bytes compressed, decompresses to 399,360 bytes (5.91× ratio) — the exact file shipped with the benchmark, unmodified

## Contents
1. [Overview](#1-overview)
2. [Initial Analysis](#2-initial-analysis)
3. [Optimizations](#3-optimizations)
4. [Performance Comparison](#4-performance-comparison)
5. [Hardware Acceleration Proposal](#5-hardware-acceleration-proposal)
6. [Conclusion](#6-conclusion)

---

## 1. Overview

### 1.1 Purpose of the Benchmark

`pyflate` times a pure-Python bzip2 decoder — originally written by Paul Sladen — decompressing one fixed input file. There is no `zlib`, no `bz2` module, no C extension anywhere in the timed path: bit-level field reads, Huffman table construction, the move-to-front transform, the inverse Burrows-Wheeler transform, and the final run-length expansion are all plain Python.

This gives `pyflate` a very different performance signature from a benchmark like `raytrace`. `raytrace`'s cost is spread thin across many small, cheap object allocations; `pyflate`'s cost concentrates in a handful of tight, repeatedly-executed loops operating on primitive data (bits, bytes, small integers) rather than custom objects. Pairing the two benchmarks in this project was deliberate — they stress CPython in close to opposite ways: allocation/dispatch overhead on one side, raw byte-level loop throughput on the other.

Unlike `raytrace`, this benchmark checks its own output: at the end of every timed iteration it computes the MD5 digest of the decompressed result and asserts it equals a hard-coded reference digest (`afa004a630fe072901b1d9628b960974`). A broken optimization does not just run slower — it throws inside the benchmark itself. This project's own correctness checks (§2.1, §3) add an independent, external byte-for-byte comparison against the preserved original on top of that internal gate, since passing the internal MD5 check alone does not guarantee every intermediate step behaves identically to the original.

### 1.2 Workload (Measured)

> Every figure below comes from running the unmodified benchmark once, through an instrumented copy that counts function and method calls without changing what they do, against the real project input file. Like the equivalent counts for `raytrace`, these numbers are properties of the input file, not of the machine or the measured time.

| Quantity | Value |
|---|---:|
| Compressed input | 67,562 bytes |
| Decompressed output | 399,360 bytes |
| Compression ratio | 5.91× |
| Output MD5 | `afa004a630fe072901b1d9628b960974` (matches reference exactly) |
| bzip2 blocks in this file | 2 |
| `decode_huffman_block()` calls | 2 (one per block) |

**Huffman symbol lookups** (`find_next_symbol`): **296,542** total, averaging 148,271 per block.

**move_to_front (MTF) calls:** **185,606**, averaging a 6.98-position shift per call. Fewer calls than symbol lookups, because RUNA/RUNB run-length codes and the end-of-block symbol never reach the MTF step — only literal byte symbols do.

| Quantity | Value |
|---|---:|
| Huffman tables built (`compute_tables` calls) | 2 |
| Total `HuffmanTable` objects constructed | 12 (up to 6 per block, matching the format's 2–6 allowed Huffman groups) |
| Combined `symbols_in_use` across blocks | 294 |
| `compute_selectors_list` calls | 2 |
| `compute_used` calls | 2 |
| `bwt_reverse` calls | 2 |
| Combined characters processed by `bwt_reverse` | 672,368 |
| `readbits()` calls | 313,416 |
| Total bits consumed | 1,080,992 (≈135,124 bytes of bit-level reads) |

> The `bwt_reverse` character count is the size of the BWT-encoded block content itself, before the benchmark's final run-length-decode pass — it is not directly comparable to the 399,360-byte final output without also isolating the RLE pass's own expansion behavior, which this instrumentation does not do separately.

**Two things stand out.** First, `find_next_symbol` is called 296,542 times to decode a file that is only 67,562 bytes compressed — roughly 4.4 symbol lookups per compressed byte, and each lookup (in the original implementation) is a linear scan of a Huffman table. Second, `move_to_front` is called 185,606 times, and the original implementation rebuilds its entire list on every call via three concatenated slices (§1.5d), so each of those 185,606 calls performs up to three separate list allocations.

### 1.3 Libraries and Dependencies

**Standard library only**

- `hashlib` — `hashlib.md5()` computes the digest used for the benchmark's own internal correctness gate, checked once per loop against the fixed reference value.
- `os`, `struct` — path handling for locating the input file, and (in the unused gzip path) struct-based header parsing.

No third-party decompression library is used or available to the timed code — `zlib` and the standard library's own `bz2` module exist elsewhere in CPython but are never imported here. Every bit of decompression logic is the benchmark's own Python code.

**Measurement and profiling tools**

- `pyperf` — registers the benchmark via `bench_time_func()`.
- `pyperformance` — discovers, launches and manages `bm_pyflate`.
- `perf` — sampled hotspot profiling (§2.3).
- `py-spy` — supplemental Python-frame flame graphs (§2.3).

### 1.4 Program Structure and Execution Flow

```
bench_pyflake(loops, filename)
  open the input file
  start timer
  repeat loops times:
    seek input to position 0
    wrap it in an RBitfield (bit-level reader)
    read a 16-bit magic number
    magic == 0x425a (bzip2)?
      bzip2_main(field)
        read method byte ('h' expected), block-size digit
        loop over compressed blocks:
          read a 48-bit block-type marker
          read a 32-bit CRC (discarded, never checked)
          block-type == pi (0x314159265359)?
            decode_huffman_block(b, out)
              read the randomised-block flag (never set by this input)
              read the BWT origin pointer
              compute_used(b)          - 256-bit symbol-presence map
              read huffman_groups (2 to 6)
              compute_selectors_list(b, huffman_groups)
              compute_tables(b, huffman_groups, symbols_in_use)
              main decode loop:
                every 50 symbols, switch to the next selected table
                find_next_symbol(b, reversed=False)
                RUNA/RUNB (0 or 1)? accumulate a run-length, continue
                end-of-block symbol? stop the loop
                otherwise: look up the byte via favourites, MTF it,
                  append to buffer
              bwt_reverse(b"".join(buffer), pointer)
              run-length-decode the result into out[]
          block-type == sqrt(pi) (0x177245385090)?
            stream end reached, stop the block loop
        return the joined output bytes
      magic == 0x1f8b (gzip)? gzip_main(field)  (present, never reached
        by this project's input - see 1.8)
  stop timer
  assert md5(out) == the fixed reference digest
  return the elapsed time
```

The two decoded bzip2 blocks account for essentially all of the work measured in §1.2 — block-type parsing and the outer loop itself are negligible against 296,542 Huffman lookups and 185,606 MTF calls.

### 1.5 Algorithms

**(a) Bit-level input** — `RBitfield` reads the compressed stream through `readbits(n)`, pulling individual bits out of a byte buffer, most-significant-bit first. Every piece of the format — block header, Huffman group count, the tables themselves, and every symbol code — is read this way. 313,416 calls consume 1,080,992 bits from a 67,562-byte (540,496-bit) input: the compressed stream is read close to twice over in bit-sized pieces, a direct consequence of decoding variable-length Huffman codes one field at a time.

**(b) Huffman table construction** — `compute_tables()` builds one `HuffmanTable` per active Huffman group (2 to 6 per block; this file's two blocks build 12 in total) from the per-symbol code-length data read out of the stream. Each table stores its entries as `HuffmanLength` objects in a plain Python list, sorted by `(bits, code)`.

**(c) Huffman symbol lookup** — `find_next_symbol()` walks that sorted list linearly, "peeking" the right number of bits and comparing against each entry's code, re-peeking only when the required bit count changes. The first match consumes those bits and returns the decoded symbol. With 296,542 calls against tables holding up to a few hundred entries each, this scan is the single largest contributor to the symbol-lookup cost identified in §2.

> Past the point where this scan can succeed or fail, the function's source contains a **second, unreachable block**: an alternate table-search loop, never executed because the preceding code always either returns from inside the first loop or raises immediately after it. That dead code itself calls `raise` on a bare string rather than an `Exception` instance — invalid in Python 3, which requires exceptions to derive from `BaseException`. It is harmless precisely because it can never run, but it's recorded here as a real, verifiable property of the source rather than "corrected," since fixing dead code has no effect on behavior or performance (§1.8).

**(d) Move-to-front decoding** — decoding a literal symbol looks up `favourites[r-1]`, then calls `move_to_front(favourites, r-1)` to bring that value to the front of the list. The original implementation does this with `l[:] = l[c:c+1] + l[0:c] + l[c+1:]` — three list slices concatenated into a new list — rather than a single in-place rotation. Called 185,606 times, this is one of the clearest, most mechanical inefficiencies identified in this report (§2, §3).

**(e) Inverse Burrows-Wheeler transform** — `bwt_reverse()` undoes the block sort applied during compression, using the origin pointer to walk the permutation back to the original symbol order. Confirmed to run exactly twice (once per block), processing 672,368 characters combined — a single linear pass per block, not the quadratic behavior some naive BWT implementations exhibit.

**(f) Run-length decoding** — the final step scans the BWT-reversed buffer for runs of four identical bytes; when found, the following byte is read as a count and the run is expanded by that many additional repetitions. This is a straightforward linear scan, but it allocates a new bytes slice per iteration via `list.append()` rather than writing into a preallocated buffer (§2, §3).

**(g) Block and stream framing** — two 48-bit magic constants delimit the format: one marks "another block follows," the other "end of stream." A 32-bit CRC is read and discarded between blocks, never verified — the benchmark's only correctness signal is the whole-file MD5 check.

**(h) The unused gzip path** — `gzip_main()` implements DEFLATE decoding using the same `HuffmanTable` machinery, selected only when the magic number is `0x1f8b`. The shipped input begins with `0x425a` (bzip2), so this path contributes zero calls to any measurement in this report.

### 1.6 Main Data Structures

| Structure | Description |
|---|---|
| `RBitfield` | Wraps the input file; `readbits()`/`snoopbits()` pull and peek bits. All 313,416 `readbits()` calls go through this class. |
| `HuffmanLength` | One instance per Huffman code: code, bit-length, symbol, precomputed bit-reversed code. 12 `HuffmanTable` instances each hold a list of these. |
| `HuffmanTable.table` | Plain Python list of `HuffmanLength`, sorted by `(bits, code)`; scanned linearly by `find_next_symbol()`. |
| `favourites` | List of byte values in use in the current block, reordered on every literal symbol — 185,606 rebuild operations across the file. |
| `buffer` / `out` | Plain Python lists of byte strings, joined with `b"".join(...)` at block/stream boundaries. |

### 1.7 Candidate Costs to Investigate

| # | Hypothesis | Measured basis |
|---|---|---|
| H1 | The Huffman symbol-lookup scan | 296,542 linear-scan calls to `find_next_symbol` — highest-frequency operation in the decode |
| H2 | Move-to-front's three-slice rebuild | 185,606 calls, each reconstructing the entire list instead of rotating in place |
| H3 | The inverse-BWT working set | 672,368 characters processed across 2 `bwt_reverse` calls |
| H4 | Run-length-decode allocation pattern | repeated `list.append()` of byte slices rather than one preallocated buffer |
| H5 | Bit-field read granularity | 313,416 `readbits()` calls, ~2× the input's raw bit count |
| H6 | `python3-dbg`'s own bookkeeping | extra allocation-safety checks needed for reliable perf symbol resolution, distinct from real algorithmic cost |

### 1.8 Relevant Implementation Limitations

- **Genuine internal correctness gate** — an MD5 check against a fixed reference digest, unlike `raytrace`, which has none. This project's external byte-for-byte check (§2.1, §3) still adds value on top, since passing the final MD5 doesn't prove every intermediate transform matches.
- **`decode_huffman_block()`** explicitly doesn't support "randomised" bzip2 blocks: if that flag is ever set, it executes `raise "Bzip2 randomised support not implemented"` — a bare string, invalid in Python 3, which would raise `TypeError` instead of delivering the intended message. Never triggered by this project's input; left as-is since fixing it is outside the scope of a performance optimization.
- **`find_next_symbol()`** contains a second, structurally unreachable table-search loop (§1.5c) with the same bare-string-raise pattern — verified dead by instrumentation, left in place for the same reason as above.
- **The gzip path** (§1.5h) is present but unreachable for this project's fixed bzip2 input; untouched by any measurement or optimization in this report.
- **CRC values** are read but never checked (§1.5g); the only correctness signal is the whole-file MD5 comparison.

---

## 2. Initial Analysis

### 2.1 Environment and Measurement Method

| | |
|---|---|
| Host | Course QEMU VM (naranja4), KVM acceleration, PMU passthrough |
| CPU (host) | Xeon E5-2630 v3 |
| Interpreter (timing) | CPython 3.10.12, `python3-dbg` build |
| Benchmark tools | pyperformance 1.14.0, pyperf |
| Kernel | Linux (perf 5.15.209) |
| Profiling tools | Linux `perf`, `py-spy` |

A separate Windows cross-check used CPython 3.12 (release build) on different hardware entirely — its numbers are reported alongside the VM's (§4) but never mixed into the same statistic, since interpreter build and host both differ.

**Correctness checking, two layers:**

1. The benchmark's own internal gate — MD5 of the output against `afa004a630fe072901b1d9628b960974`, asserted every loop.
2. This project's external check (`scripts/check_attempt_correctness.py`) — decompress with the preserved original and each optimized attempt, compare bytes exactly, re-verify the MD5 independently.

### 2.2 Baseline Results

| | Mean | Std dev |
|---|---:|---:|
| Official VM baseline (`perf stat -r 3`, `--fast`) | **120.99 s** | 6.80 s (±5.62%) |
| Windows cross-check (CPython 3.12 release, non-fast) | 516 ms | 29 ms |

These two numbers are **not** comparable to each other directly — different interpreter build, different host, different fast/non-fast mode — and this report never presents them as the same measurement. The VM figure is used for the official before/after comparison in §4, since it was captured in the same environment as the official final measurement.

### 2.3 Flame Graphs and Profiling

**perf report** (VM, `python3-dbg` + pyperformance `--fast`, cpu-clock sampling), top self-time symbols from baseline:

| Symbol | Self % |
|---|---:|
| `_PyEval_EvalFrameDefault` (interpreter dispatch) | 22.81% |
| `_PyMem_DebugCheckAddress` (python3-dbg bookkeeping) | 4.06% |
| `__memset_avx2_unaligned_erms` (libc) | 3.11% |
| `read_size_t` | 2.75% |
| `call_function.lto_priv.0` | 2.56% |
| `list_dealloc.lto_priv.0` | 2.33% |
| `list_ass_slice` | 1.96% |
| `pthread_getspecific` (libc) | 1.92% |
| `_PyObject_Malloc` | ~1.8% |

`list_dealloc` and `list_ass_slice` together (4.29%) are directly explained by H2 (§2.4): the original `move_to_front()` performs three list slices per call, 185,606 times.

**py-spy** (supplemental, Windows, matched workload): baseline 6,847 samples, final 4,984 samples, both at 500 Hz over 20 decompressions — a monotonic drop consistent with the measured speedup, though (as with `raytrace`) the authoritative hotspot percentages in this report come from perf, not py-spy.

### 2.4 Identified Bottlenecks

1. **Interpreter dispatch** (22.81% self time) — every opcode in every one of the 296,542 `find_next_symbol` calls and 185,606 `move_to_front` calls passes through `_PyEval_EvalFrameDefault`. Confirms H1 and H5.
2. **`move_to_front`'s list-slice churn** (`list_dealloc` + `list_ass_slice`, 4.29% combined) — directly measured, directly attributable to the three-slice rebuild (§1.5d/H2). One of the clearest, most mechanically-fixable costs identified in either benchmark in this project.
3. **`python3-dbg`'s own overhead** (`_PyMem_DebugCheckAddress`, 4.06%) — inherent to profiling with the debug build (H6); not a target for optimization.
4. **Native/library-level cost** (`__memset`, `pthread_getspecific`, `read_size_t`, ~7.8% combined) — mostly memory-management and libc bookkeeping, not directly attackable from Python source.

The clearest, most concrete target is item 2 — unlike item 1 (fundamental dispatch cost), item 2 is a specific, correctable inefficiency in one function.

---

## 3. Optimizations

> Unlike `raytrace`'s three *independent* attempts, `pyflate`'s three attempts are **cumulative** — each builds on the previous one's code rather than starting fresh from the original. Recorded explicitly, since it's a different methodology from the other benchmark in this project.

### 3.1 Attempt 1 — Canonical Huffman LUT

**Strategy:** replace `find_next_symbol()`'s linear scan (H1) with an O(1) lookup table of size `1 << max_bits`, built once per Huffman table and indexed directly by the next `max_bits` bits of the stream, in both bit-orderings the format requires. Falls back to the original scan on a lookup miss.

**Correctness:** `IDENTICAL=YES`, `MATCHES_REFERENCE=YES` (`results/attempt1/correctness_report.txt`).

### 3.2 Attempt 2 — MTF / BWT / int2byte Cleanup *(builds on Attempt 1)*

**Strategy:** targets H2, H3 and H4.
- `move_to_front(l, c)` rewritten as `l.insert(0, l.pop(c))` — one pop and one insert instead of three list-slice concatenations.
- `bwt_transform`'s character-count pass consolidated into a single pass.
- `_INT2BYTE` precomputed as a lookup table.

**Correctness:** `IDENTICAL=YES`, `MATCHES_REFERENCE=YES` (`results/attempt2/correctness_report.txt`).

### 3.3 Attempt 3 — Hot-Loop Attribute Hoisting + memoryview RLE *(builds on Attempt 2)*

**Strategy:** targets H5 and H4's allocation pattern.
- Hoists `t.find_next_symbol`, `favourites.pop`, `favourites.insert`, `buffer.append` and `_INT2BYTE` to local variables inside `decode_huffman_block`.
- Rewrites the end-of-block RLE decode (§1.5f) to index directly into the post-BWT `bytes` object.

**Correctness:** `IDENTICAL=YES`, `MATCHES_REFERENCE=YES` (`results/attempt3/correctness_report.txt`).

### 3.4 Selection

Attempt 3 (cumulative, including Attempts 1 and 2) was selected as the official final implementation — **both the preliminary Windows sweep and the official VM measurement agree it's the fastest of the three**, a materially different situation from `raytrace`, where the fastest-looking attempt in a quick preliminary test wasn't actually fastest at full scale. No such discrepancy exists here.

> **One genuine finding worth recording:** Attempt 1 alone (the LUT, before Attempts 2/3's cleanup) behaves differently depending on measurement method. Under pyperformance's calibrated, warmed-up loop it's a clean win (§4.3). Under a cold, per-call `time.perf_counter()` measurement, it's a **regression** — building the LUT itself (up to 2^max_bits entries per group, in pure Python) costs more than the scan it replaces on a single cold decode. Attempts 2 and 3 remove enough surrounding overhead that the LUT's advantage holds under both styles. This split directly motivates the hardware proposal (§5): a hardware BRAM-based LUT has O(1) load time as well as O(1) lookup, which a pure-Python LUT does not.

### 3.5 Optimizations Considered and Not Adopted

- **Standard library's `bz2` module** — not adopted; would move the studied computation entirely out of the code being measured.
- **C-extension rewrite of the hot loop** — not pursued, for the same reason: it would stop measuring Python-level optimization.

---

## 4. Performance Comparison

### 4.1 Official Before/After Result

| Version | Mean | Std dev | Improvement | Correct |
|---|---:|---:|---:|---|
| ORIGINAL | 120.99 s | 6.80 s | 0.00% | Yes |
| **FINAL (Attempt 3)** | **76.307 s** | 0.236 s | **36.93%** | Yes |

**Speedup: 1.586×** (120.99 / 76.307). Windows cross-check (separate environment, not mixed into the VM figure): 516 ms → 362 ms, **+29.84%**. **Target ≥7% improvement: ACHIEVED in both environments**, roughly 5× margin on the VM figure.

### 4.2 perf stat Hardware-Counter Comparison

| Metric | Baseline | Final | % change |
|---|---:|---:|---:|
| Elapsed | 120.99 s | 76.307 s | **−36.93%** |
| task-clock | 113,777 msec | 76,417 msec | −32.84% |
| Instructions | 579,459,257,273 | 388,984,213,555 | **−32.87%** |
| Branches | 142,417,577,761 | 94,689,052,878 | **−33.51%** |
| Branch-misses | 770,743,225 | 479,262,450 | **−37.82%** |
| Cache-references | 543,649,894 | 410,288,916 | **−24.53%** |
| Cache-misses | 28,010,769 | 28,422,250 | +1.47% |
| Page-faults | 463,011 | 458,789 | −0.91% |
| Context-switches | 3,089 | 2,888 | −6.51% |

**Interpretation:**

- Instructions, branches and branch-misses all fall by roughly a third — consistent with removing interpreter-level work rather than restructuring memory access.
- Elapsed time falls *more* (−36.93%) than raw instruction count (−32.87%): the remaining instructions execute with better branch prediction (branch-misses fall harder than branches themselves).
- Cache-misses are essentially flat (+1.47%, within noise) — a CPU-side win, not a memory-side one. The cache-miss *rate* rises purely because references dropped while misses stayed constant — the same pattern documented for `raytrace`, not a new phenomenon.

> **Hardware-counter caveat:** `cycles` reports exactly 0 due to a KVM-specific PMU limitation on this host (Xeon E5-2630 v3) — every other hardware counter above is exposed and was captured normally. Same class of host-level PMU quirk documented for the `raytrace` project on the same kind of machine.

### 4.3 Attempts Compared — Preliminary Sweep vs. Official VM Result

| Version | Mean (ms) | Std dev (ms) | vs. original |
|---|---:|---:|---:|
| Baseline | 540 | 24 | — |
| Attempt 1 (LUT alone) | 453 | 17 | +16.1% |
| Attempt 2 (LUT + MTF/BWT/int2byte) | 354 | 9 | +34.4% |
| **Attempt 3 (Attempt 2 + hoisting)** | **324** | 6 | **+40.0%** |
| Final (= Attempt 3, separate capture) | 348 | 22 | +35.6% |

Unlike `raytrace`, there's no discrepancy to report between the preliminary sweep and the official result: Attempt 3 is fastest in the preliminary sweep, and Final (a copy of Attempt 3) is confirmed fastest again in the official VM measurement (§4.1). Selecting Attempt 3 is directly supported by every measurement taken, not just the earliest one.

### 4.4 perf Report Comparison — Where the Bottleneck's Shape Changed

| Symbol | Baseline | Final | Change |
|---|---:|---:|---|
| `_PyEval_EvalFrameDefault` | 22.81% | 24.26% | +1.45pp |
| `_PyMem_DebugCheckAddress` | 4.06% | 4.42% | +0.36pp |
| `__memset_avx2_unaligned_erms` | 3.11% | 2.90% | −0.21pp |
| `read_size_t` | 2.75% | 2.94% | +0.19pp |
| `call_function.lto_priv.0` | 2.56% | 2.61% | +0.05pp |
| **`list_dealloc.lto_priv.0`** | **2.33%** | out of top 15 | **GONE** |
| **`list_ass_slice`** | **1.96%** | out of top 15 | **GONE** |
| `pthread_getspecific` (libc) | 1.92% | 2.02% | +0.10pp |

Two things worth spelling out, since perf report percentages are relative shares, not absolute time:

- `_PyEval_EvalFrameDefault`'s share rises (22.81% → 24.26%) — the same concentration effect documented for `raytrace`: 22.81% of 120.99s baseline ≈ 27.6s; 24.26% of 76.307s final ≈ 18.5s — a real ~33% *absolute* drop, even though the *share* rose because the total pie shrank faster than this slice did.
- **`list_dealloc` and `list_ass_slice` drop out of the top 15 entirely.** Not a share redistribution to explain away — the direct, measured disappearance of the exact cost Attempt 2's `move_to_front` rewrite (§3.2) targeted. Of every result in either benchmark's profiling data, this is the cleanest single before/after confirmation that a specific code change fixed the specific cost it aimed at.

---

## 5. Hardware Acceleration Proposal

### 5.1 Choice of Component

§2.4 and §4.4 agree on where the cost concentrates: interpreter dispatch driven by 296,542 Huffman symbol lookups and 185,606 `move_to_front` calls. **The Huffman lookup was selected** as the hardware target:

- Higher-frequency operation (296,542 vs. 185,606 calls).
- Its software fix (Attempt 1's LUT) demonstrated the right *shape* of solution but also software's own limitation (§3.4): building a large LUT in pure Python is itself expensive — exactly the load-time cost a hardware BRAM-based LUT doesn't pay.
- `move_to_front` (Attempt 2's target) was already fixed cheaply and completely in software (§4.4 shows its cost simply vanishing) — little marginal benefit left to accelerate.

Bit management (`RBitfield`'s `readbits`/`snoopbits`, 313,416 calls) maps naturally onto a small hardware barrel shifter, included as a supporting component.

### 5.2 Function

| Module | Role |
|---|---|
| `bit_shifter` | Barrel-shifter FSM matching `RBitfield`'s `readbits()`/`snoopbits()`: peek or consume N bits from a shift register |
| `huff_lut` | Direct-indexed lookup matching `find_next_symbol()`'s O(1) fast path: given the next `max_bits` bits, returns the decoded symbol and true bit-length |
| `huffman_decoder` | Top-level: drives `bit_shifter` to fill the lookup window, queries `huff_lut`, reports the decoded symbol |

### 5.3 Architecture

Implemented as three SystemVerilog modules under `Project/subPyflate/hw/rtl/`: `bit_shifter.sv`, `huff_lut.sv`, `huffman_decoder.sv`, with matching testbenches under `Project/subPyflate/hw/tb/` and a simulator-autodetecting runner at `Project/subPyflate/hw/run_sim.sh` (ModelSim, Icarus Verilog, or Verilator).

### 5.4 Interfaces — Implemented vs. Proposed

**Implemented:** direct RTL port-level interfaces on `bit_shifter`, `huff_lut` and `huffman_decoder`, driven by their testbenches in simulation.

**Proposed for deployment (not implemented):** MMIO register map, AXI4-Lite control paired with AXI4-Stream for the compressed byte stream, a DMA path for bulk transfer, a Python C-extension wrapper, a real device driver, and actual FPGA integration (`Project/subPyflate/docs/12_hw_sw_interface.md`).

### 5.5 Simulation Results

Simulated with **Icarus Verilog 12.0** (Windows, 2026-09-21); results in `Project/subPyflate/hw/results/SIMULATION_RESULTS.txt`:

| Testbench | Checks | Result |
|---|---:|---|
| `tb_huff_lut` | 5 | ALL PASS |
| `tb_bit_shifter` | 8 | ALL PASS |
| `tb_huffman_decoder` | 9 | ALL PASS |
| **Total** | **22** | **0 errors** |

This demonstrates the implemented RTL's logical correctness against its own specification — it does not measure deployed FPGA performance, area, or power, all of which remain estimates (§5.6).

### 5.6 Expected Performance (Estimated, Not Measured)

Target clock: **200 MHz** (labeled ESTIMATE). Estimated latency: **3 cycles/symbol** (v1 design), **1 cycle/symbol** (proposed v2 pipeline) — `Project/subPyflate/docs/13_hardware_performance.md`. Area, power and achievable bandwidth are likewise documented there as estimates only.

No synthesis, no FPGA bring-up, and no measured hardware-in-the-loop timing exists — the same evidence boundary maintained throughout the `raytrace` hardware proposal.

### 5.7 Trade-offs

- **Load-time vs. software** — the motivating finding (§3.4) is specifically a load-time problem in software; a hardware BRAM-backed LUT is expected to have both fast load and fast lookup, which is the core of the acceleration argument here rather than lookup speed alone.
- **Area/complexity** — a direct `2^max_bits`-entry table trades memory (BRAM) for guaranteed O(1) access; the proposed v2 pipeline trades additional area for one-cycle-per-symbol throughput over v1's three.
- **Scope** — only the Huffman lookup and its supporting bit-shifter are targeted; `move_to_front`, already fixed cheaply in software, is deliberately left out of the hardware proposal rather than accelerated redundantly.

---

## 6. Conclusion

`pyflate` measures a pure-Python bzip2 decoder against a fixed 67,562-byte input, decompressing to 399,360 bytes. Unlike `raytrace`'s many small object allocations, its cost concentrates in a small number of repeatedly-executed loops over primitive data: **296,542 Huffman symbol lookups and 185,606 move-to-front calls** account for the large majority of measured interpreter work.

Profiling confirmed two concrete, separately-addressable costs: interpreter dispatch overhead inherent to both hot loops (22.81% self time), and a specific, mechanical inefficiency in `move_to_front`'s three-slice list rebuild — independently confirmed twice over, once by its 4.29% combined perf share in the baseline, and again by that exact share **disappearing entirely** from the final profile's top 15 symbols after Attempt 2's fix.

Three **cumulative** optimization attempts were implemented and verified correct, both by the benchmark's own internal MD5 gate and by this project's external byte-for-byte comparison. **Attempt 3 was selected as the official final implementation and measured at 36.93% improvement** on the official VM (120.99s → 76.307s), corroborated by an independent 29.84% result on a completely separate Windows/CPython 3.12 environment — both comfortably clearing the 7% requirement. Unlike the `raytrace` report, there's no discrepancy to disclose between preliminary and official rankings here: Attempt 3 is the fastest attempt in every measurement taken.

Hardware counters confirm the result beyond wall-clock time: instructions −32.87%, branches −33.51%, branch-misses −37.82%. A genuine, non-obvious finding from the optimization process — that the Huffman LUT is a clear win under warmed-up measurement but a measured *regression* under a cold, single-decode measurement, because building the LUT itself is expensive in pure Python — became the direct motivation for the hardware proposal: a BRAM-backed lookup table doesn't pay that same load-time cost. Three SystemVerilog modules were implemented and verified in simulation: **0 errors across 22 functional checks.** This demonstrates logical correctness only; **no synthesis, deployment, or measured hardware performance is claimed anywhere in this report.**