# HW1: Code Profiling, Optimization, and HWSW Understanding

## 1. General Approach
We implemented a deterministic DNA motif evolution workload in C++. A circular sequence of 2-bit bases (A/C/G/T) is updated over many iterations using 5-neighbor pattern scoring. This gives a non-trivial, compute-heavy loop that is suitable for profiling.

Why this workload:
- Meaningful sequence-processing style computation.
- Hot loop sensitive to branches, data reuse, and instruction throughput.
- Easy correctness checks via deterministic seed + checksum.

## 2. Unoptimized Implementation (hw1_naive.cpp)
### What it does
- Generates sequence values in `[0..3]` from a fixed seed.
- Runs `iterations` evolution steps.
- For each index, reads a 5-base neighborhood and computes score using explicit branch conditions.
- Prints final checksum and base counts.

### Why it is not optimized
- Rebuilds neighborhood encoding from scratch for each position.
- Branch-heavy scoring in the inner loop.
- Repeated index arithmetic and memory loads.

### Profiling Results (fill with your measurements)
- Runtime (wall): `____` sec
- `cycles`: `____` (or N/A)
- `instructions`: `____` (or N/A)
- `IPC = instructions/cycles`: `____` (or N/A)
- `cache-misses`: `____` (or N/A)
- `branch-misses`: `____` (or N/A)
- `task-clock`: `____`

## 3. Optimized Implementation (hw1_optimized.cpp)
### Optimization change
We applied two equivalent transformations:
1. Precompute a 1024-entry LUT for all 5-mer scores (`4^5` patterns).
2. Use a rolling encoded window to derive the next 5-mer by bit-shift + one incoming base.

This preserves identical output while reducing hot-loop overhead.

### Why this optimization
- Eliminates repeated branch evaluation from the critical path.
- Reduces redundant neighborhood recomputation.
- Improves inner-loop predictability and throughput.

### Hardware-level insight
Branch-heavy, recomputation-heavy loops often underperform due to control-flow and per-element instruction overhead. LUT + rolling-window converts the kernel to a more regular operation stream, typically improving IPC and lowering cycles/task-clock.

### Profiling Results (fill with your measurements)
- Runtime (wall): `____` sec
- `cycles`: `____` (or N/A)
- `instructions`: `____` (or N/A)
- `IPC = instructions/cycles`: `____` (or N/A)
- `cache-misses`: `____` (or N/A)
- `branch-misses`: `____` (or N/A)
- `task-clock`: `____`

## 4. Comparison and Discussion
### Key observations
- Runtime speedup: `____x` (naive / optimized)
- Cycle/task-clock reduction: `____%`
- Branch/cache metric change: `____%`

### Explanation
(Write 1-2 short paragraphs connecting your counters to behavior. Suggested points: fewer branches in hot loop, less recomputation, and better instruction/data path regularity.)

### Unexpected outcomes (optional)
(Describe any metric that did not improve as expected and why.)

## 5. Correctness Validation
Both binaries run with identical `(length, iterations, seed)` and compare checksums. The script exits with an error if checksums differ.

## 6. AI Usage Disclosure
Prompts used are listed in `ai_prompts_used.txt`.

## 7. Reproducibility Commands
Use:
```bash
chmod +x run_hw1_profile.sh
./run_hw1_profile.sh 300000 20 123456789
```
Perf outputs are saved to:
- `results/perf_naive.txt`
- `results/perf_optimized.txt`
