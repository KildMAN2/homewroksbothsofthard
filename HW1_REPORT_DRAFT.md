# HW1: Code Profiling, Optimization, and HWSW Understanding

## 1. General Approach and Thought Process
I chose an iterative image denoising kernel (3x3 box blur repeated over a large 2D image). This workload is meaningful because it appears in graphics and signal processing pipelines, and it is large enough to reveal hardware effects such as memory locality and cache behavior.

I intentionally wrote two versions of exactly the same computation:
- A direct naive implementation that repeatedly loads overlapping neighborhoods.
- An optimized implementation that reuses partial sums.

Both versions use deterministic input generation from a fixed seed and print a checksum, so correctness can be validated automatically.

## 2. Unoptimized Implementation (`hw1_naive.cpp`)
### Why this baseline was chosen
The naive baseline is straightforward and easy to reason about. For each interior pixel, it sums all 9 neighbors directly from the input image and writes one output value. This is a common first implementation style.

### What the program does
- Input: `width height iterations seed`
- Creates a deterministic pseudo-random grayscale image.
- Repeats blur updates for `iterations` steps.
- Keeps border pixels unchanged.
- Prints final checksum and elapsed time.

### Why it is not optimized
- Adjacent output pixels recompute overlapping sums and reload many of the same input bytes.
- The kernel performs redundant memory reads and creates extra pressure on the memory hierarchy.

### Profiling results (measured on this environment)
Run configuration: `1024 x 1024`, `30` iterations, seed `123456789`

- Runtime (`time`): ~`0.10` sec
- `perf task-clock`: `119.21 ms`
- `context-switches`: `13`
- `cpu-migrations`: `0`
- `page-faults`: `636`

Note: Hardware counters (`cycles`, `instructions`, `cache-misses`) were unavailable in this sandboxed environment, so software counters were collected. On a normal Linux machine with PMU access, the same script attempts hardware counters first.

## 3. Optimized Implementation (`hw1_optimized.cpp`)
### What change was made
I rewrote the 3x3 blur as a separable two-stage computation:
1. Horizontal pass: precompute 3-pixel sums per row.
2. Vertical pass: combine three horizontal sums and divide by 9.

This is mathematically equivalent to the original box blur and preserves exact output for interior pixels.

### Why this optimization
- Reduces redundant data loads.
- Improves spatial locality by streaming through memory in regular passes.
- Moves work from repeated neighbor fetches to reusable intermediate values.

### Hardware/software insight behind the change
The naive version repeatedly touches overlapping neighborhoods, which can underutilize data reuse opportunities and increase memory traffic. The two-pass version improves data reuse explicitly and tends to reduce pressure on caches and load/store units, which lowers runtime.

### Profiling results (measured on this environment)
Run configuration: `1024 x 1024`, `30` iterations, seed `123456789`

- Runtime (`time`): ~`0.05` sec
- `perf task-clock`: `41.53 ms`
- `context-switches`: `1`
- `cpu-migrations`: `0`
- `page-faults`: `1152`

## 4. Comparison of Results
### Key improvements
- Checksum is identical in both versions: `14415896786458145035`.
- Wall-clock speedup is approximately `2.0x` (`0.10 / 0.05`).
- `task-clock` improved from `119.21 ms` to `41.53 ms` (about `2.87x` better).

### Why the gain makes sense
The optimization removes major redundancy in neighborhood reads and makes memory access more structured. Since this workload is dominated by repeated stencil operations over large arrays, better reuse of loaded data strongly improves throughput.

### Interesting caveat
Page-fault counts are not directly comparable as a pure kernel metric in short runs and can be affected by process and memory state. For architectural analysis, hardware PMU counters (`cycles`, `instructions`, cache events) on a local machine would provide a deeper explanation.

## 5. Correctness and Reproducibility
The script verifies correctness by comparing checksums and exits with an error if they differ.

Commands used:
```bash
chmod +x run_hw1_profile.sh
./run_hw1_profile.sh 1024 1024 30 123456789
```

Outputs:
- `results/perf_naive.txt`
- `results/perf_optimized.txt`

## 6. Approaches Considered but Not Used
I considered adding multithreading, but did not include it because the assignment focus can be demonstrated clearly with single-threaded microarchitectural optimization and exact output preservation.

## 7. AI Usage
Prompts used for AI assistance are documented in `ai_prompts_used.txt`.
