# Pyflate — Benchmark Understanding

Source of truth for what the benchmark does, so later profiling / optimization
choices are grounded in code, not guesses.

## 1. Purpose

`pyflate` is a **pure-Python decompressor** for gzip (DEFLATE) and bzip2. The
pyperformance benchmark measures how long it takes to decompress a fixed input
file (`interpreter.tar.bz2`, ~840 KB when compressed, several MB expanded) and
verifies the result against a hardcoded MD5.

The benchmark stresses:
- bit-level I/O in Python (`readbits` / `snoopbits`),
- Huffman decoding (a long linear scan through a table of `HuffmanLength`
  objects for every emitted symbol),
- Move-to-front (MTF) list rotation,
- Burrows-Wheeler transform inversion,
- byte-level RLE unpack.

Every operation runs at the interpreter level with per-symbol Python object
overhead — that is exactly the property that makes optimization worthwhile and
makes a hardware accelerator meaningful.

## 2. Benchmark Source

- File in pyperformance: `pyperformance/data-files/benchmarks/bm_pyflate/run_benchmark.py`
- Preserved copy: `Project/subPyflate/original/bm_pyflate/run_benchmark.py`
- pyproject.toml: `Project/subPyflate/original/bm_pyflate/pyproject.toml`
  (declares `[tool.pyperformance] name = "pyflate"`)

## 3. Entry Point

Bottom of the file:

```python
if __name__ == '__main__':
    runner = pyperf.Runner()
    runner.metadata['description'] = "Pyflate benchmark"
    filename = os.path.join(os.path.dirname(__file__),
                            "data", "interpreter.tar.bz2")
    runner.bench_time_func('pyflate', bench_pyflake, filename)
```

`bench_pyflake(loops, filename)`:
- Opens the file in binary.
- Runs `loops` iterations of "seek to 0, wrap with `RBitfield`, read magic,
  dispatch to `gzip_main` or `bzip2_main`, decompress fully".
- Timed region is exactly the decompression loop.
- After the loop it MD5s the last decompressed output and requires the digest
  to equal `"afa004a630fe072901b1d9628b960974"`.

## 4. Execution Flow

```
open(filename)
  │
  ├─► for each loop iteration:
  │     seek(0)
  │     field = RBitfield(file)
  │     magic = field.readbits(16)
  │     ├─ 0x1f8b -> gzip_main(field)  (DEFLATE)
  │     └─ 0x425a -> bzip2_main(field) (bzip2)  <-- taken for interpreter.tar.bz2
  │
  └─► MD5(out) == "afa004a630fe072901b1d9628b960974"
```

Because the workload starts `0x425a` (`"BZ"`), only the **bzip2 path** is
exercised by the benchmark. `gzip_main` is preserved for correctness but is
not timed.

## 5. Bzip2 Path Detail (`bzip2_main` -> `decode_huffman_block`)

For each bzip2 block:
1. Read `blocktype` (48 bits) and CRC (32 bits).
2. On the "pi" magic, run `decode_huffman_block(b, out)`:
   1. Skip `randomised` bit + read 24-bit pointer.
   2. `compute_used(b)` -> which of 256 symbols are present.
   3. Read `huffman_groups` (2..6).
   4. `compute_selectors_list(b, groups)` -> list of table indices.
   5. `compute_tables(b, groups, symbols_in_use)`:
      - `groups` Huffman tables built from delta-coded 5-bit lengths.
   6. Main loop:
      - Every 50 symbols, switch to the next Huffman table.
      - `r = t.find_next_symbol(b, False)` — **primary hotspot**.
      - Symbols 0..1 accumulate an RLE "repeat" counter, symbol N-1 = end,
        others map to `favourites[r-1]` after a Move-to-Front rotation.
   7. `bwt_reverse(joined, pointer)` inverts the Burrows-Wheeler transform.
   8. Byte-level RLE decode into `out`.

## 6. Main Functions (per-file line pointers)

| Function | Location (line, verified against preserved source) | Role |
|---|---|---|
| `bench_pyflake` | ~end | Timed loop. |
| `bzip2_main` | mid | Bzip2 block dispatcher. |
| `decode_huffman_block` | mid | Main bzip2 decode. |
| `HuffmanTable.find_next_symbol` | mid | **Hot Huffman lookup** (linear scan). |
| `HuffmanTable.populate_huffman_symbols` | mid | Canonical code + reverse-bit assignment. |
| `Bitfield.readbits` / `snoopbits` | early | Bit reader for gzip. |
| `RBitfield.readbits` / `snoopbits` | early | Bit reader for bzip2 (MSB-first). |
| `move_to_front` | mid | List splice per symbol. |
| `bwt_transform` / `bwt_reverse` | mid | BWT inverse. |
| `gzip_main` | late | Not exercised by the pyperformance workload. |

## 7. Data Structures

- `Bitfield` / `RBitfield` : integer bit-shift buffer over a file-like object.
- `HuffmanLength` : one object per code — carries `(code, bits, symbol,
  reverse_symbol)`.
- `HuffmanTable.table` : Python `list` of `HuffmanLength`, sorted by
  `(bits, code)`. Iterated linearly by `find_next_symbol`.
- `favourites` : Python `list[bytes]` of length `symbols_in_use - 2`, rotated
  by MTF for every real symbol.
- `buffer` / `out` : Python `list[bytes]`, joined once with `b"".join(...)`.

## 8. Input / Workload

- File: `interpreter.tar.bz2` shipped with pyperformance.
- Size: approximately 840 KB compressed. Decompressed content is a Python
  interpreter tarball.
- Bzip2 blocksize marker: `'9'` typically (900k blocks).
- Deterministic — the MD5 check guarantees identical output across runs.

## 9. Output

- Full uncompressed bytes as a single `bytes` object returned by `bzip2_main`
  (and then MD5-checked).

## 10. Dependencies

- Python (3.10 in the VM baseline; verify with `python3-dbg --version`).
- `pyperf` (via pyperformance).
- Stdlib only: `hashlib`, `os`, `struct`.

No C extension is involved for the actual decompression — every operation runs
in the interpreter. That is exactly why pure-Python profiling is meaningful
here.

## 11. Exact Benchmark Command

Normal (VM):
```
python3-dbg -m pyperformance run --bench pyflate
```

Direct invocation of the preserved runner (also used for correctness checks):
```
python3-dbg Project/subPyflate/original/bm_pyflate/run_benchmark.py --loops=1
```

Cheap development run (fast mode):
```
python3-dbg -m pyperformance run --bench pyflate --fast
```

## 12. Supported Arguments

`bench_time_func` under `pyperf` accepts standard pyperf flags: `--loops`,
`--processes`, `--values`, `--fast`. The benchmark itself takes no
domain-specific arguments (unlike raytrace's `--width`/`--height`). The
workload is fixed by the shipped data file.

## 13. Initial Computational Observations (before profiling)

- The Huffman `find_next_symbol` walks a Python list of up to `symbols_in_use`
  `HuffmanLength` objects **for every emitted symbol**. Each iteration touches
  Python attributes and calls `field.snoopbits(x.bits)` when the bit-length
  changes. This is expected to dominate `decode_huffman_block`.
- `Bitfield.readbits` / `RBitfield.readbits` are called at least once per
  symbol (often more). Each call performs Python integer arithmetic and
  attribute lookup — not vectorizable in pure Python.
- `move_to_front(l, c)` uses `l[:] = l[c:c+1] + l[0:c] + l[c+1:]`, which
  allocates three new list slices for every symbol.
- `bwt_transform` calls `F.find(int2byte(i))` 256 times as a bytes scan; on a
  block up to 900k bytes this is many megabytes of scanning per block.
- `int2byte(...)` (a `struct.Struct(">B").pack`) is invoked per literal byte
  and per MTF rotation; precomputing a table shaves per-call C overhead.

These observations are **hypotheses**, verified by the profiling stage
(docs/03, docs/04).

## 14. Initial Bottleneck Hypotheses

Ranked (highest expected impact first):
1. `HuffmanTable.find_next_symbol` (O(#codes) per symbol).
2. `RBitfield.readbits` / `snoopbits` (call frequency).
3. `move_to_front` (list-slice rotation).
4. `bwt_transform` (256 linear scans, per block).
5. Byte-level RLE unpack (`nt[i] == nt[i+1] == ...`).
6. `int2byte` per byte.

Confirmation and quantitative shares come from `docs/03_profiling.md` and
`docs/04_bottleneck_analysis.md`.
