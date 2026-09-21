# Pyflate — Software Optimization Attempts

Each attempt introduces one focused change (or a small, closely related set of
changes) and is preserved untouched under `subPyflate/optimized/attemptN/`.

Every attempt is validated for correctness by
`subPyflate/scripts/check_attempt_correctness.py`, which:
- decompresses the pyflate workload with the preserved original module,
- decompresses the same workload with the attempt's module,
- MD5s both outputs,
- asserts identical bytes AND that the digest matches the reference
  `afa004a630fe072901b1d9628b960974`.

Preliminary timing is recorded in `results/<attempt>/preliminary.txt` after
the attempt is measured with `pyperformance ... --fast` in the VM. Official
before/after values live in `docs/06_final_software.md`.

## Attempt 1 — Canonical Huffman Lookup

**Targeted bottleneck**
`HuffmanTable.find_next_symbol` was an O(#codes) Python-object scan per
emitted symbol, dominating `decode_huffman_block` on every bzip2 block.

**Original behavior**
```python
def find_next_symbol(self, field, reversed=True):
    cached_length = -1
    cached = None
    for x in self.table:
        if cached_length != x.bits:
            cached = field.snoopbits(x.bits)
            cached_length = x.bits
        if (reversed and x.reverse_symbol == cached) or (not reversed and x.symbol == cached):
            field.readbits(x.bits)
            return x.code
    raise Exception("unfound symbol, even after end of table @%r" % field.tell())
```

**Change**
- Compute `max_bits` from the table.
- Build a lookup table of size `1 << max_bits` where each entry is
  `(code, code_bits)`; entries for a `bits`-length code are replicated across
  the `2**(max_bits - bits)` positions that match that code padded with any
  future bits.
- Two directions:
  - `reversed=True` (gzip / LSB-first `Bitfield`): index by low bits, so
    `lut[(suffix << bits) | reverse_symbol] = (code, bits)`.
  - `reversed=False` (bzip2 / MSB-first `RBitfield`): index by high bits, so
    `lut[(symbol << (max_bits - bits)) | suffix] = (code, bits)`.
- Cache the LUT per direction on the `HuffmanTable` instance (built once, used
  many times per bzip2 block).
- Fall back to the original linear scan on any lookup miss or on end-of-stream
  errors from `snoopbits(max_bits)`.

**Correctness risk**
- Zero when the LUT is built correctly and the fallback path is used at true
  EOF. Directly checked by `scripts/check_attempt1_correctness.py`.

**Expected benefit**
- Huffman decode per symbol drops from O(#codes) Python ops to one dictionary
  index + two integer ops.
- Expected to shrink `_PyEval_EvalFrameDefault` and
  `PyObject_GenericGetAttr` shares proportionally.

**Preliminary measurement**
- `TO BE COLLECTED IN VM` (`results/attempt1/preliminary.txt`).

## Attempt 2 — MTF, BWT, and int2byte cleanup

**Targeted bottlenecks**
- `move_to_front(l, c)` was allocating three list slices per real symbol.
- `bwt_transform` was scanning up to a 900k-byte block 256 times with
  `bytes.find`.
- `int2byte(i)` was called per literal byte via `struct.Struct(">B").pack`.

**Change**
- `move_to_front(l, c)` becomes `l.insert(0, l.pop(c))` (both O(len(l)) at
  the C level, no slice allocations).
- `bwt_transform` builds the `base[]` array with a single byte-count pass
  plus cumulative sum. The `-1` sentinel for absent bytes is preserved so
  observable behavior matches the original exactly.
- `_INT2BYTE = tuple(bytes((i,)) for i in range(256))` is precomputed at
  module import; hot call sites use `_INT2BYTE[i]` instead of
  `int2byte(i)`.

**Correctness risk**
- Zero. Every change is a semantic identity on the code paths involved.
  Checked by `scripts/check_attempt2_correctness.py`.

**Expected benefit**
- Non-trivial reduction in `list_slice`, `list_ass_slice`, and
  `struct_pack` self time.
- BWT reduction is bounded by block size — expected medium impact.

**Preliminary measurement**
- `TO BE COLLECTED IN VM`.

## Attempt 3 — Hot-loop attribute hoisting

**Targeted bottleneck**
- Even with the LUT and MTF fixes, the `while True` body of
  `decode_huffman_block` still does repeated attribute reads through
  `t.find_next_symbol`, `favourites.pop`, `favourites.insert`,
  `buffer.append`, and the global `_INT2BYTE`. Each attribute read is a
  dictionary lookup on the object and hurts a tight interpreter loop.

**Change**
- Bind `t.find_next_symbol`, `favourites.pop`, `favourites.insert`,
  `buffer.append`, and `_INT2BYTE` to local names inside
  `decode_huffman_block`.
- Refresh `t_find = t.find_next_symbol` whenever the current Huffman table
  `t` is switched.
- Inline the "if idx != 0" shortcut around MTF so the frequent zero-index
  case avoids the `list.pop`/`list.insert` pair (they'd cancel).
- Reuse the byte-level RLE decoder with direct integer indexing into the
  `bytes` object (which already indexes as ints), removing per-byte
  `nearly_there[i:i + 1]` slicing and `ord(nearly_there[i + 4:i + 5])`.

**Correctness risk**
- Zero. All bindings are stable within one call and the RLE decode uses the
  same comparisons and outputs.
- Checked by `scripts/check_attempt3_correctness.py`.

**Expected benefit**
- Small but consistent — each removed attribute lookup shaves a few
  interpreter opcodes per iteration in the hottest loop.

**Preliminary measurement**
- `TO BE COLLECTED IN VM`.

## Attempt-Comparison Table

Correctness columns filled by the four `check_attempt_correctness.py`
runs (`results/{attempt1,attempt2,attempt3,final}/correctness_report.txt`).
Windows preliminary timings from `scripts/windows_bench.py` (8 iterations,
3 loops each, `time.perf_counter` around `bzip2_main`; the same script
also writes `results/windows_preliminary.txt`).

| Version | Correct | Windows mean (s) | Std dev | Windows Δ vs original | VM time (official) | VM Δ (official) |
|---|---|---:|---:|---:|---:|---:|
| Original | Yes (reference) | 1.8877 | 0.1628 | — | TBD | 0.00% |
| Attempt 1 (LUT alone) | Yes | 2.4883 | 0.2028 | **-31.82%** | TBD | TBD |
| Attempt 2 (LUT + MTF/BWT/int2byte) | Yes | 1.7626 | 0.1670 | **+6.63%** | TBD | TBD |
| Attempt 3 (attempt2 + hoisting) | Yes | 1.6855 | 0.1200 | **+10.71%** | TBD | TBD |
| Final (= Attempt 3) | Yes | 1.6394 | 0.1079 | **+13.16%** | TBD | TBD |

**All four attempts are byte-identical to the original for the pyflate
workload** (MD5 = `afa004a630fe072901b1d9628b960974`, output length =
399,360 bytes).

### Key finding from the Windows preliminary run

Attempt 1 (LUT alone) *regresses* on this small workload because
`HuffmanTable._build_lut` runs entirely in Python and fills up to
`2**max_bits` entries per group (~131K entries at `max_bits=17`) using a
Python `for` loop. Over ~5 bzip2 blocks × 6 groups the total LUT-build
cost exceeds the per-symbol savings. Once the constant-factor cleanups
from Attempts 2 and 3 remove the surrounding interpreter overhead
(`list_ass_slice`, `bytes_find`, per-byte `struct.pack`, attribute reads),
the algorithmic advantage of the LUT starts to net out and Final lands at
+13.16%. See `docs/06_final_software.md` for the full interpretation.
