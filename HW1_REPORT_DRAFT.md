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

### Profiling results (measured on this environment)
Run config: `length=300000`, `iterations=20`, `seed=123456789`

- Runtime (wall): `0.25 sec`
- `perf task-clock`: `460.47 ms`
- `context-switches`: `23`
- `cpu-migrations`: `0`
- `page-faults`: `270`

Note: this environment does not expose PMU hardware counters (`cycles`, `instructions`, `cache-misses`), so software counters were collected.

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

### Profiling results (measured on this environment)
Run config: `length=300000`, `iterations=20`, `seed=123456789`

- Runtime (wall): `0.01 sec`
- `perf task-clock`: `14.31 ms`
- `context-switches`: `3`
- `cpu-migrations`: `0`
- `page-faults`: `272`

## 4. Comparison of Results
### Key improvements
- Correctness preserved: both versions produced identical checksum `492632665203353383` and identical base counts.
- Wall time improved from `0.25 sec` to `0.01 sec` (about `25x`).
- `task-clock` improved from `460.47 ms` to `14.31 ms` (about `32.2x`).

### Why the gain makes sense
The naive version spends significant work on repeated branch evaluation and rebuilding neighborhood patterns per index. The optimized version hoists this work into precomputation (LUT) and lightweight rolling updates. This reduces dynamic instruction count and branch pressure in the hot path, so throughput improves substantially.

### Caveat
Page faults are similar between runs and are not the primary explanatory metric here. For deeper microarchitectural analysis, run on a machine with hardware counter access and compare `cycles`, `instructions`, and branch miss events.

## 5. Correctness and Reproducibility
The script compares checksums and exits with error if they differ.

Commands:
```bash
chmod +x run_hw1_profile.sh
./run_hw1_profile.sh 300000 20 123456789
```

Outputs:
- `results/perf_naive.txt`
- `results/perf_optimized.txt`

## 6. Approaches Considered but Not Used
I considered thread-level parallelism but kept the study single-threaded to isolate core algorithm/data-path effects for clearer HW/SW interpretation.

## 7. AI Usage
Prompts used for AI assistance are documented in `ai_prompts_used.txt`.
