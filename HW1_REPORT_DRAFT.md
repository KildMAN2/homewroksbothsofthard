# HW1: Code Profiling, Optimization, and HWSW Understanding

## 1. General Approach and Thought Process
I selected a deterministic DNA motif evolution simulation in C++. The program evolves a circular DNA-like sequence (A/C/G/T encoded as 2-bit values) across many iterations. Each position updates based on a 5-base neighborhood scoring rule.

This task is meaningful because pattern scoring over large sequences is common in computational biology and sequence analytics, and it creates strong opportunities for CPU-level optimization.

I implemented two versions with identical behavior:
- Naive: branch-heavy motif scoring and direct neighborhood loads per position.
- Optimized: precomputed score lookup table (LUT) plus rolling 5-mer window encoding.

Both versions generate the same deterministic input from a seed and print checksum/base counts for correctness validation.

## 2. Unoptimized Implementation (hw1_naive.cpp)
### Why this baseline was chosen
It is the direct, readable implementation of the model. For each sequence index, it explicitly reads five neighbors and computes score with multiple conditional branches.

### What the program does
- Input: `length iterations seed`
- Initializes sequence values in `[0..3]` using xorshift RNG.
- Repeats update rule for `iterations` rounds.
- Emits final checksum and base histogram (`A/C/G/T`).

### Why it is not optimized
- Recomputes neighborhood encoding from scratch for every position.
- Uses many branches in scoring, which can reduce throughput.
- Performs modulo/index operations and redundant loads in the inner loop.

### Profiling results (measured on KVM VM, naranja4)
Run config: `length=4000000`, `iterations=50`, `seed=123456789`

- Runtime (wall): `8.684 sec`
- `cpu-clock`: `8666.29 ms`
- `instructions`: `21,136,918,723`
- `cache-references`: `1,589,872`
- `cache-misses`: `14,814` (0.932% of cache refs)
- `branches`: `2,400,362,572`
- `branch-misses`: `257,521,029` (**10.73%** — high misprediction rate)
- `context-switches`: `80`
- `page-faults`: `2,084`

Note: `cpu-cycles` reports 0 due to a known KVM PMU mapping quirk; all other hardware counters are valid.

## 3. Optimized Implementation (hw1_optimized.cpp)
### What change was made
Two optimizations were applied while preserving exact algorithm behavior:
1. Build a `1024`-entry LUT for all 5-mer pattern scores (since each base is 2 bits, `4^5 = 1024`).
2. Use a rolling encoded window so each next index reuses previous state instead of rebuilding the full 5-mer.

### Why this optimization
- Removes repeated branch-heavy score evaluation from the hot loop.
- Reduces redundant loads and index math by incremental window updates.
- Improves instruction path regularity and CPU efficiency.

### Hardware/software insight behind the change
When inner loops are branch-heavy and repeatedly recompute local state, IPC tends to suffer. Converting condition-heavy scoring into LUT reads and shifting the encoded window turns the hot loop into a more predictable stream of operations with lower per-element overhead.

### Profiling results (measured on KVM VM, naranja4)
Run config: `length=4000000`, `iterations=50`, `seed=123456789`

- Runtime (wall): `0.552 sec`
- `cpu-clock`: `551.50 ms`
- `instructions`: `4,914,880,559`
- `cache-references`: `605,828`
- `cache-misses`: `11,347` (1.873% of cache refs)
- `branches`: `410,098,509`
- `branch-misses`: `24,108` (**0.01%** — near-perfect prediction)
- `context-switches`: `4`
- `page-faults`: `2,084`

## 4. Comparison of Results
### Key improvements
- Correctness preserved: both versions produced identical checksum and base counts.
- Wall time improved from `8.684 sec` to `0.552 sec` — **~15.7x speedup**.
- `cpu-clock` improved from `8666.29 ms` to `551.50 ms` — **~15.7x**.
- Instructions reduced from `21.1B` to `4.9B` — **4.3x fewer**.
- Branch misses dropped from `257,521,029` (10.73%) to `24,108` (0.01%) — **~10,000x fewer mispredictions**.
- Cache misses: `14,814` vs `11,347` — roughly similar (both small).

### Why the gain makes sense
The dominant factor is **branch misprediction**: the naive version mispredicts 10.75% of all branches, causing frequent pipeline flushes. The optimized version (LUT + rolling window) eliminates condition-heavy scoring, dropping branch mispredictions to near zero (0.01%). Combined with 4.3x fewer instructions from the rolling window reuse, total execution time drops ~15.7x.

Cache behavior is similar between both versions since the working set fits in cache, confirming the gain is purely from control-flow and instruction-count improvement.

## 5. Correctness and Reproducibility
The script compares checksums and exits with error if they differ.

Commands:
```bash
chmod +x run_hw1_profile.sh
./run_hw1_profile.sh 4000000 50 123456789
```

Outputs:
- `results/perf_naive.txt`
- `results/perf_optimized.txt`

## 6. Approaches Considered but Not Used
I considered thread-level parallelism but kept the study single-threaded to isolate core algorithm/data-path effects for clearer HW/SW interpretation.

## 7. AI Usage
Prompts used for AI assistance are documented in `ai_prompts_used.txt`.
