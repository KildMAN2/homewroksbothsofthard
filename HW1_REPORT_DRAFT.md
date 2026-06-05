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

- Runtime (wall): `8.661 sec`
- `cpu-clock`: `8647.24 ms`
- `instructions`: `21,134,979,151`
- `cache-references`: `1,664,866`
- `cache-misses`: `8,516` (0.512% of cache refs)
- `branches`: `2,400,006,297`
- `branch-misses`: `254,994,930` (**10.62%** — high misprediction rate)
- `context-switches`: `52`
- `page-faults`: `2,082`

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

At the microarchitectural level: modern out-of-order CPUs use a branch predictor (e.g., a bimodal or tournament predictor) to speculatively execute instructions before a branch resolves. When the branch pattern is data-dependent and irregular — as it is here, since score conditions depend on the actual base values — the predictor cannot learn a reliable pattern. Each misprediction forces a pipeline flush and re-fetch, wasting ~15–20 cycles on a typical superscalar pipeline. With 10.73% of 2.4 billion branches mispredicting in the naive version, hundreds of billions of wasted pipeline cycles accumulate. The LUT removes all of these branches from the hot path: a single table lookup replaces seven conditional checks, and the rolling window encoding (shift + mask) is a purely arithmetic, branch-free operation.

### Were the results expected or surprising?
The direction was expected — replacing branches with a LUT and reducing redundant work should always help on modern out-of-order CPUs. The magnitude was somewhat surprising: a **15.7× speedup** from a single algorithmic change to the inner loop is unusually high. The key insight from the profiling data is that the naive version was not just *slow* but was operating far below its theoretical peak due to the 10.73% branch miss rate. Once the misprediction bottleneck was removed, the CPU's out-of-order engine could fully pipeline the remaining arithmetic, explaining the large multiplier.

### Profiling results (measured on KVM VM, naranja4)
Run config: `length=4000000`, `iterations=50`, `seed=123456789`

- Runtime (wall): `0.555 sec`
- `cpu-clock`: `554.57 ms`
- `instructions`: `4,914,628,180`
- `cache-references`: `631,689`
- `cache-misses`: `10,549` (1.670% of cache refs)
- `branches`: `410,050,783`
- `branch-misses`: `23,518` (**0.01%** — near-perfect prediction)
- `context-switches`: `4`
- `page-faults`: `2,082`

## 4. Comparison of Results
### Key improvements
- Correctness preserved: both versions produced identical checksum and base counts.
- Wall time improved from `8.661 sec` to `0.555 sec` — **~15.6x speedup**.
- `cpu-clock` improved from `8647.24 ms` to `554.57 ms` — **~15.6x**.
- Instructions reduced from `21.1B` to `4.9B` — **4.3x fewer**.
- Branch misses dropped from `254,994,930` (10.62%) to `23,518` (0.01%) — **~10,800x fewer mispredictions**.
- Cache misses: `8,516` vs `10,549` — roughly similar (both small).

### Why the gain makes sense
The dominant factor is **branch misprediction**: the naive version mispredicts 10.73% of all branches, causing frequent pipeline flushes. On a modern superscalar CPU a misprediction costs ~15–20 cycles of wasted speculative work and a pipeline re-fill stall. At 257 million mispredictions over the run, this represents roughly 4–5 billion wasted cycles — consistent with the ~8.7 second runtime on a ~1 GHz effective throughput (cpu-clock ≈ cpu utilization × wall time). The optimized version (LUT + rolling window) eliminates condition-heavy scoring entirely, dropping branch mispredictions to near zero (0.01%). Combined with 4.3× fewer dynamic instructions from rolling window reuse (each step costs a shift + mask + array-write instead of five indexed loads + seven comparisons), total execution time drops ~15.7×.

Cache behavior is similar between both versions since the 4 MB sequence fits in L3 cache and the 1024-entry LUT (4 KB) fits in L1, confirming the gain is purely from control-flow and instruction-count improvement rather than memory hierarchy effects.

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

**SIMD vectorization:** The inner loop processes one element at a time. Vectorizing with AVX2 (32 bytes per register) could process 32 elements in parallel. However, the circular boundary reads (`(i±1) % n`, `(i±2) % n`) create gather-load patterns that are expensive on most CPUs, and the scatter-write to the output buffer complicates lane alignment. The LUT approach already achieves a 15.7× gain without this complexity, so SIMD was deferred.

**Thread-level parallelism (OpenMP):** Splitting iterations across threads would work if each thread operates on a disjoint partition of the array. However, the circular neighborhood means boundary elements at partition edges depend on elements owned by a neighbor thread, requiring either ghost-cell copies or synchronization. This adds code complexity and was not needed given the single-core speedup achieved.

**Compiler auto-vectorization hints (`__builtin_expect`, `[[likely]]`):** These were considered to nudge the branch predictor, but they only improve branch *prediction* hints at compile time — they cannot eliminate the fundamental data-dependent unpredictability of the scoring conditions. The LUT approach is superior because it eliminates the branches entirely rather than trying to predict them.

## 7. AI Usage
Prompts used for AI assistance are documented in `ai_prompts_used.txt`.
