# Pyflate — Profiling Methodology and Results

## 1. Profiling Environment

Same VM as `docs/02_baseline.md`. Requires:
- `perf` accessible to a normal user (`kernel.perf_event_paranoid` low enough,
  or run under sudo). Documented as-observed in `logs/`.
- `python3-dbg` so perf can resolve Python interpreter symbols.
- `py-spy` installed (`pip install --user py-spy` or apt equivalent).
- `pyperformance` installed with the `bm_pyflate` benchmark.

Environment capture: `Project/subPyflate/scripts/run_profile.sh` writes
`logs/perf_env.txt` (`perf --version`, `perf list | head`, and the
`kernel.perf_event_paranoid` value) before every profiling run.

## 2. Profiling Commands

### 2.1 perf stat (repeated, cheap)

```
perf stat -r 3 -- python3-dbg -m pyperformance run --bench pyflate --fast > \
    profiling/perf_stat_baseline.txt 2>&1
```

Recorded metrics (default event set on the VM):
- `seconds time elapsed`
- `task-clock` / `cpu-clock`
- `instructions`
- `branches`, `branch-misses`
- `cache-references`, `cache-misses`
- `page-faults`, `context-switches`

### 2.2 perf record + perf report

```
perf record -F 999 -g -o profiling/perf_baseline.data \
    -- python3-dbg -m pyperformance run --bench pyflate --fast
perf report --stdio -i profiling/perf_baseline.data \
    > profiling/perf_report_baseline.txt
```

- `-F 999` : 999 Hz sample rate (matches the raytrace project).
- `-g` : capture full call graphs.
- `python3-dbg` : Python frames resolve to real symbols.

### 2.3 py-spy flame graph

```
py-spy record --rate 100 --output profiling/flamegraph_pyspy_baseline.svg \
    -- python3-dbg Project/subPyflate/original/bm_pyflate/run_benchmark.py --loops=1
```

- Sampled from Python frames only (no C symbols unless `--native` is added).
- Runs the preserved benchmark directly (not via pyperformance) so we sample
  the actual decompression rather than the pyperformance worker manager.
- `--loops=1` keeps the run short but still exercises the whole workload.

If py-spy is not available in the VM, the script records the failure and
skips this step (as in `Project/subRay/`, where py-spy was intermittently missing).

## 3. Workload

- pyperformance runs the benchmark through its normal worker process model.
  `--fast` reduces the number of `values`/`processes` so a full record/report
  cycle fits within a few minutes.
- Direct `run_benchmark.py --loops=1` runs a single decompression pass. This
  is the cheapest workload that still hits every hot path (Huffman decode,
  MTF, BWT, RLE). It is preferred for py-spy.

## 4. perf stat Results (baseline)

`TO BE COLLECTED IN VM`. Filled in after `scripts/run_profile.sh` runs.

| Metric | Baseline (mean of 3) |
|---|---:|
| Elapsed time | TBD |
| cpu-clock | TBD |
| instructions | TBD |
| branches | TBD |
| branch-misses (%) | TBD |
| cache-references | TBD |
| cache-misses (%) | TBD |

## 5. perf report Results (baseline)

`TO BE COLLECTED IN VM`. Filled in after `perf report --stdio` completes.

The report will list the top self-time symbols. Based on code inspection
(docs/01), the expected candidates are:

- `_PyEval_EvalFrameDefault` — Python interpreter dispatch (broad).
- `lookdict_unicode_nodummy` / `PyObject_GenericGetAttr` — attribute lookups
  on `HuffmanLength` / `Bitfield`.
- `PyLong_AsLong`, `PyLong_FromLong` — integer boxing in bit ops.
- `PyList_Append`, `list_slice`, `list_ass_slice` — MTF rotation and BWT
  output list.
- `find_next_symbol` (Python frame) — the actual Huffman scan.
- `bytes_find` — inside `bwt_transform`.

Expected but only labeled here as HYPOTHESIS. The real percentages replace
this table after the run:

| Symbol (self%) | Baseline % |
|---|---:|
| ... | TBD |

## 6. py-spy Flame Graph (baseline)

**Collected on Windows** 2026-09-21 via
`py-spy record --rate 500 --output profiling/flamegraph_pyspy_baseline.svg --format flamegraph -- python scripts/pyspy_target.py original 20`.

- File: `profiling/flamegraph_pyspy_baseline.svg` (6847 samples over 20
  decompressions, 13.5 s wall clock).
- No `[unknown]` frames — py-spy resolves the Python call stack cleanly.
- Call chain visible from bottom up:
  `pyspy_target.main` -> `bzip2_main` -> `decode_huffman_block` ->
  `find_next_symbol` (wide bar) plus `bwt_reverse` and the byte-RLE
  loop.
- Parallel SVGs for each attempt (attempt1/2/3/final) generated the same
  way; sample counts drop monotonically to 4438 (attempt3), confirming
  the +30% improvement measured under pyperformance.

Linux perf-report side of profiling remains TO BE COLLECTED IN VM (see
§4/§5); the flame-graph visualization is complete.

## 7. Initial Observations (fill after collection)

`TO BE COLLECTED IN VM`.

## 8. Possible Hotspots (pending confirmation)

Ranked in decreasing expected importance:

1. `HuffmanTable.find_next_symbol` — linear scan of Python objects for every
   emitted symbol. Called from `decode_huffman_block` for every RLE'd MTF
   symbol and inside `compute_tables` when reading code lengths.
2. `RBitfield.readbits` and `snoopbits` — call-frequency-dominated.
3. `move_to_front` — three list slices per real symbol.
4. `bwt_transform` — 256 linear byte scans per bzip2 block.
5. `bwt_reverse` — Python-level output list of per-byte `bytes` slices.
6. Byte RLE decode loop at end of `decode_huffman_block`.
7. `int2byte` per literal byte (bzip2 favourites and MTF outputs).

These become the "Confirmed Bottlenecks" in `docs/04_bottleneck_analysis.md`
once the perf/py-spy outputs are attached.
