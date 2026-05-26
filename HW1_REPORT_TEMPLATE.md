# HW1: Code Profiling, Optimization, and HWSW Understanding

## 1. General Approach
We implemented a deterministic iterative image denoising workload in C++. The kernel repeatedly applies a 3x3 box blur over a large grayscale image. This creates a memory-intensive loop nest that is suitable for `perf`-based microarchitectural analysis.

Why this workload:
- Non-trivial and compute-heavy over large input sizes.
- Strong interaction between algorithm structure and cache behavior.
- Easy to preserve exact correctness using deterministic initialization and checksum.

## 2. Unoptimized Implementation (`hw1_naive.cpp`)
### What it does
- Generates an image with pseudo-random bytes from a fixed seed.
- Runs `iterations` blur steps.
- In each step, for each interior pixel, directly loads all 9 neighboring values and computes `sum/9`.
- Borders are kept unchanged.

### Why it is not optimized
- Repeats many redundant memory loads between adjacent pixels.
- Poor temporal reuse in the inner loop: adjacent outputs reload overlapping neighborhoods.
- Straightforward implementation prioritizes readability over data reuse.

### Profiling Results (fill with your measurements)
- Runtime (wall): `____` sec
- `cycles`: `____`
- `instructions`: `____`
- `IPC = instructions/cycles`: `____`
- `cache-misses`: `____`
- `branch-misses`: `____`

## 3. Optimized Implementation (`hw1_optimized.cpp`)
### Optimization change
We replaced direct 3x3 summation with a separable two-pass formulation:
1. Horizontal pass computes 3-pixel sums and stores them in an intermediate buffer.
2. Vertical pass combines three horizontal sums and divides by 9.

This is mathematically equivalent to the original 3x3 box blur for interior pixels, and preserves identical output.

### Why this optimization
- Reduces repeated memory accesses by reusing horizontal partial sums.
- Improves spatial locality and cache utilization.
- Decreases total arithmetic and load pressure for the same final computation.

### Hardware-level insight
Modern CPUs are often memory-hierarchy sensitive. The naive kernel repeatedly fetches overlapping neighborhoods from L1/L2/L3, causing higher data movement. Precomputing horizontal sums converts the kernel into a more cache-friendly streaming pattern that typically lowers cycles and improves IPC.

### Profiling Results (fill with your measurements)
- Runtime (wall): `____` sec
- `cycles`: `____`
- `instructions`: `____`
- `IPC = instructions/cycles`: `____`
- `cache-misses`: `____`
- `branch-misses`: `____`

## 4. Comparison and Discussion
### Key observations
- Runtime speedup: `____x` (naive / optimized)
- Cycle reduction: `____%`
- Cache-miss change: `____%`
- IPC change: `____%`

### Explanation
(Write 1-2 short paragraphs connecting your counters to behavior. Suggested points: lower data movement from reuse, fewer redundant loads, improved cache line utilization, and why that maps to lower cycles.)

### Unexpected outcomes (optional)
(Describe any metric that did not improve as expected and why that may happen.)

## 5. Correctness Validation
Both binaries are run with identical `(width, height, iterations, seed)` and compare checksums. The script exits with error if checksums differ.

## 6. AI Usage Disclosure
Prompts used are listed in `ai_prompts_used.txt`.

## 7. Reproducibility Commands
Use:
```bash
chmod +x run_hw1_profile.sh
./run_hw1_profile.sh 4096 4096 20 123456789
```
Perf outputs are saved to:
- `results/perf_naive.txt`
- `results/perf_optimized.txt`
