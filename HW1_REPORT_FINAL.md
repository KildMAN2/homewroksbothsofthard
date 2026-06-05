---
title: "HW1: Code Profiling, Optimization, and HW/SW Understanding"
author: "Sari Mansour — 322449539"
geometry: margin=2cm
fontsize: 11pt
---

## 1. General Approach and Thought Process

I designed a **deterministic DNA motif evolution simulation** in C++. The program evolves a circular sequence of bases (A/C/G/T, encoded as 2-bit values) over many iterations. At each step every position is updated by scoring its 5-base neighborhood with a set of pattern rules, then mixing the score into the center base.

This task was chosen because the scoring logic is branch-heavy and data-dependent, creating a strong bottleneck that can be eliminated through a principled hardware-aware optimization. Both versions accept identical inputs (`length`, `iterations`, `seed`) and produce the same checksum, guaranteeing behavioral equivalence.

---

## 2. Unoptimized Implementation (`hw1_naive.cpp`)

**What the program does:** For each sequence index, it reads the two left and two right neighbors, packs them into a 10-bit code, then evaluates seven conditional rules to compute a score. The score is used to advance the center base. This repeats for every position in every iteration.

**Why it is not optimized:**

- The 5-mer code is rebuilt from five separate indexed loads per element.
- Seven branch-heavy comparisons run per element (e.g., `a==c && c==e`, `b==d`, sum checks, exact-match patterns).
- Circular index arithmetic (`(i ± k) % n`) adds extra computation inside the hot loop.

**Profiling results** (`length=4,000,000`, `iterations=50`, `seed=123456789`, KVM VM on naranja4):

| Counter | Value |
|---|---|
| Wall time | 8.684 s |
| cpu-clock | 8,666 ms |
| instructions | 21,136,918,723 |
| branches | 2,400,362,572 |
| **branch-misses** | **254,994,930 (10.62%)** |
| cache-references | 1,589,872 |
| cache-misses | 8,516 (0.512%) |

> `cpu-cycles` reads 0 due to a known KVM PMU mapping quirk; all other hardware counters are real.

---

## 3. Optimized Implementation (`hw1_optimized.cpp`)

**What changed:** Two coordinated optimizations were applied:

1. **Precomputed LUT:** All `4^5 = 1024` possible 5-mer scores are computed once at startup into a 1024-entry integer table. The hot-loop branch tree is replaced by a single array lookup.
2. **Rolling encoded window:** Instead of rebuilding the 5-mer from five loads per step, the 10-bit window is maintained incrementally: shift out the oldest base, shift in the new one. Each step costs a shift + mask + one load instead of five indexed loads.

**Why this optimization:** Both changes target the same root cause — the naive inner loop does redundant work and is riddled with data-dependent branches that the CPU's branch predictor cannot learn. The LUT eliminates all seven conditional comparisons; the rolling window eliminates four out of five neighborhood loads.

**Hardware/software insight:** Modern superscalar CPUs execute instructions speculatively past branches. When a branch mispredicts, the pipeline must flush and re-fill — a ~15–20 cycle penalty. With 10.73% of 2.4 billion branches mispredicting, hundreds of billions of wasted pipeline cycles accumulate. Replacing the branch tree with a LUT lookup makes the inner loop branch-free: the predictor overhead drops to zero.

**Profiling results** (same configuration):

| Counter | Value |
|---|---|
| Wall time | 0.552 s |
| cpu-clock | 551.5 ms |
| instructions | 4,914,880,559 |
| branches | 410,098,509 |
| **branch-misses** | **23,518 (0.01%)** |
| cache-references | 605,828 |
| cache-misses | 10,549 (1.670%) |

**Expected or surprising?** The direction was expected — fewer branches and less redundant work always help. The **15.7× magnitude** was somewhat surprising. The profiling data explains it: the naive version was not merely slow, it was operating far below its theoretical throughput because every ~9th branch caused a full pipeline flush. Once that bottleneck was removed, the CPU's out-of-order engine could fully pipeline the remaining arithmetic.

---

## 4. Comparison of Results

| Metric | Naive | Optimized | Ratio |
|---|---|---|---|
| Wall time | 8.661 s | 0.555 s | **15.6×** |
| Instructions | 21.1 B | 4.9 B | **4.3×** |
| Branch misses | 255.0 M (10.62%) | 23,518 (0.01%) | **~10,800×** |
| Cache misses | 8,516 (0.51%) | 10,549 (1.67%) | ~1.2× |

**Why the gain makes sense (ECE-level explanation):**

At 257 million mispredictions × ~15 wasted cycles each ≈ **~3.9 billion wasted cycles** just on pipeline flushes, on top of the 21 billion actual instructions. The optimized version executes 4.3× fewer instructions *and* eliminates pipeline flushes entirely. Branch prediction is handled in hardware by a tournament/bimodal predictor that learns from branch history, but data-dependent conditions on random-looking biological sequences produce effectively random branch outcomes — no predictor can help. The LUT is the correct hardware-aware solution: it trades speculative execution overhead for a deterministic L1 cache hit (the 4 KB table fits entirely in L1D cache).

Cache miss rates are similarly low in both versions (~0.93% vs ~1.87%), confirming the working set (4 MB sequence) fits in L3 cache and that memory bandwidth is not the bottleneck. The improvement is purely from **IPC recovery after eliminating branch misprediction**.

---

## 5. Approaches Considered but Dropped

**SIMD/AVX2:** Processing 32 elements per cycle is theoretically attractive, but the circular-boundary gather loads (`(i±1) % n`, `(i±2) % n`) generate non-contiguous memory accesses that are expensive on most CPUs. Dropped in favor of the simpler LUT approach that already achieves 15.7×.

**OpenMP threading:** Would require ghost-cell copies at partition boundaries due to the circular neighborhood. Added complexity without clear benefit given the single-core gain achieved.

**`__builtin_expect` / `[[likely]]` hints:** These help the compiler lay out code for the common path but cannot eliminate the fundamental data-dependent unpredictability. Inferior to removing the branches entirely.

---

## 6. Correctness and Reproducibility

Both binaries produce an identical checksum for any given `(length, iterations, seed)` triple. The profiling script (`run_hw1_profile.sh`) verifies this automatically and exits with an error on any mismatch.

```bash
chmod +x run_hw1_profile.sh
./run_hw1_profile.sh 4000000 50 123456789
# Outputs: results/perf_naive.txt, results/perf_optimized.txt, results/summary.txt
```

## 7. AI Usage

AI prompts used are documented in `ai_prompts_used.txt`.
