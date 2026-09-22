# Pyflate — Bottleneck Analysis

Cross-references the source inspection from `docs/01` and the profiling
methodology from `docs/03`.

## 1. Profiling Evidence

- `profiling/perf_stat_baseline.txt` — perf-stat elapsed and counters.
- `profiling/perf_report_baseline.txt` — perf-report top self-time symbols
  and call graphs.
- `profiling/flamegraph_pyspy_baseline.svg` — py-spy Python-frame flame graph.
- Source: `Project/subPyflate/original/bm_pyflate/run_benchmark.py`.

## 2. Main Hotspot (HYPOTHESIS + code evidence)

**`HuffmanTable.find_next_symbol`** — called for every symbol in every bzip2
Huffman block. The current implementation is a Python `for` loop over
`self.table`, doing:

```python
for x in self.table:
    if cached_length != x.bits:
        cached = field.snoopbits(x.bits)
        cached_length = x.bits
    if (reversed and x.reverse_symbol == cached) or (not reversed and x.symbol == cached):
        field.readbits(x.bits)
        return x.code
```

Cost per symbol:
- Python attribute access on `x.bits`, `x.reverse_symbol`, `x.symbol`, `x.code`.
- Potential `snoopbits` call per unique bit-length in the table.
- On average `~|table|/2` iterations per symbol; up to |table| in the worst case.
- Table sizes reach up to `symbols_in_use` per group (usually 20..258 entries),
  ×6 groups in bzip2, ×many blocks per file.

This matches the classic pure-Python Huffman-decoder pathology and is exactly
what a canonical-Huffman lookup table (used in every real deflate/bzip2
decompressor) is designed to eliminate.

## 3. Supporting Evidence

Once perf/py-spy runs land in `profiling/`, we expect:
- `find_next_symbol` (Python frame) high in perf report self time.
- Wide `find_next_symbol` bar in py-spy.
- High `PyObject_GenericGetAttr` self time (attribute reads on `HuffmanLength`).
- High `_PyEval_EvalFrameDefault` (interpreter dispatch cost inherent to a
  large Python inner loop).

## 4. Secondary Hotspots

| # | Function | Evidence | Why it costs |
|---|---|---|---|
| 2 | `move_to_front(l, c)` | code inspection | `l[:] = l[c:c+1] + l[0:c] + l[c+1:]` — three slice allocations per real symbol; called ~once per Huffman symbol in `decode_huffman_block` and per selector in `compute_selectors_list`. |
| 3 | `RBitfield.readbits` / `snoopbits` | code inspection | Called at least once per Huffman symbol plus per bit-length change; performs Python int arithmetic and attribute updates. |
| 4 | `bwt_transform` | code inspection | 256 `bytes.find(int2byte(i))` scans over up to a 900k-byte block; each `find` is O(N) at the C level but the outer loop is Python + object churn. |
| 5 | `bwt_reverse` output | code inspection | `out.append(L[end])` builds a Python list of single bytes then joins; benign per element but multiplied by block length. |
| 6 | End-of-block RLE decode | code inspection | `nt[i] == nt[i+1] == nt[i+2] == nt[i+3]` byte compares and `nearly_there[i:i+1]` slicing per byte position; adds interpreter overhead across the whole block. |
| 7 | `int2byte(r)` | code inspection | `struct.Struct(">B").pack` per literal byte in `favourites` construction and per Huffman symbol emission. |

## 5. Bottleneck Interpretation

- Dominant cost is **the Huffman inner loop**, not memory bandwidth.
- `perf stat` is expected to show high IPC (~2+) and low cache-miss rate:
  the working set (Huffman table + bit buffer) fits easily in L1/L2.
- The heavy contributors are Python interpreter cost + object attribute
  overhead in the Huffman inner loop, plus a modest tail of list-slice cost
  in MTF and BWT.

## 6. Optimization Opportunities (candidates)

Each row explicitly says whether it targets a **software** optimization,
a **hardware** accelerator, or both.

| # | Opportunity | Target | Expected benefit | Correctness risk |
|---|---|---|---|---|
| A | Canonical-Huffman lookup table indexed by `max_bits` prefetched bits. Rewrite `find_next_symbol` to `(symbol, length) = LUT[snoopbits(max_bits)]`. | SW & HW | High. Reduces Huffman decode from O(#codes) to O(1) per symbol. Also the natural hardware kernel. | Low if built from the same `bits/reverse_symbol` values `populate_huffman_symbols` already generates. |
| B | Replace `move_to_front` slice pattern with `l.insert(0, l.pop(c))`. | SW | Medium. Two O(N) ops but no intermediate slice objects. | Zero (semantically identical). |
| C | Replace `bwt_transform`'s 256 `bytes.find` calls with a single pass counting frequencies + cumulative sum. | SW | Medium-high on large blocks. | Zero (identical output). |
| D | Precompute `_int2byte = [bytes([i]) for i in range(256)]` and use table lookup instead of `struct.pack` per byte. | SW | Small-medium (per-byte Python overhead). | Zero. |
| E | Hoist `field.snoopbits`, `field.readbits`, `favourites.pop`, `int2byte`, `out.append` into local names in the hot inner loops. | SW | Small (Python attribute-lookup shave). | Zero. |
| F | Replace `for i in range(len(L)): end = T[end]; out.append(L[end])` with a preallocated `bytearray` and index writes. | SW | Small-medium. | Zero. |
| G | Inline `favourites[r - 1]` + `move_to_front` into one operation using `list.pop(i)` + `insert(0, ...)`. | SW | Medium (folds B). | Zero. |

Candidates A/B/C/D/E are used across attempts 1/2/3 as documented in
`docs/05_optimization.md`.

## 7. Hardware Relevance (feeds docs/09)

- **A** is the natural hardware accelerator: a canonical-Huffman lookup that
  takes `max_bits` prefetched bits and returns `(symbol, length)` in a
  single cycle. It matches the profiled bottleneck exactly.
- The BWT inverse and MTF are also parallelizable, but they operate on
  variable-sized blocks and would require a much larger area budget for
  smaller gain — a bad first accelerator.
- The bit reader is a supporting piece: the accelerator needs one, but by
  itself it does not eliminate the Python-side cost.

## 8. Selected First Optimization

**Attempt 1: candidate A** — canonical-Huffman lookup table in
`HuffmanTable.find_next_symbol`.

Details, expected impact, correctness plan, and results tracked in
`docs/05_optimization.md`.
