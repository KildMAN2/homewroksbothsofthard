# Phase 1 and Phase 2 - Benchmark Plan (Project)

## Phase 1: Selected 2 Benchmarks

1. nbody
2. mdp

### Why this pair

- nbody provides a clear floating-point compute hotspot with straightforward profiling and optimization reasoning.
- mdp is the harder benchmark: branch-heavy state transitions, irregular control flow, and more complex reasoning for both software and hardware optimization.
- Together they produce a strong contrast and a stronger report narrative than two similar microbenchmarks.

---

## Phase 2: Understand Each Benchmark

## Benchmark A: nbody

### Source location (pyperformance)

- Repository path: pyperformance/data-files/benchmarks/bm_nbody/run_benchmark.py

### What operation it tests

- Simulates gravitational interaction among celestial bodies.
- Repeatedly computes pairwise forces, updates velocity and position, and measures energy.

### Main modules and calls

- Uses pyperf for benchmark timing.
- Main flow goes through:
  - offset_momentum(...)
  - report_energy(...)
  - advance(dt, iterations, ...)

### Core data structures and algorithm

- Bodies are represented as tuples/lists containing:
  - position vector [x, y, z]
  - velocity vector [vx, vy, vz]
  - mass m
- A precomputed pair list is used for all body-body interactions.
- Force update is dominated by repeated floating-point arithmetic inside nested loops.

### Bottleneck summary

- High arithmetic intensity (multiply/add/power operations) in tight loops.
- Runtime dominated by pairwise force computation and state updates.

### Hardware acceleration idea

- Floating-point/vector acceleration unit for force accumulation (especially inverse-distance and fused multiply-add style updates).

---

## Benchmark B: mdp (hard benchmark)

### Source location (pyperformance)

- Repository path: pyperformance/data-files/benchmarks/bm_mdp/run_benchmark.py

### What operation it tests

- Evaluates a Markov Decision Process style battle model by repeatedly expanding successor states and evaluating expected outcomes.

### Main modules and calls

- Uses pyperf for timing.
- Main benchmark entry calls Battle().evaluate(...).
- Heavy internal work happens through successor-generation and transition-application methods.

### Core data structures and algorithm

- State objects and successor collections representing possible actions/transitions.
- Repeated evaluation with tolerance/termination logic.
- Irregular branch-heavy control flow and many small updates to intermediate state.

### Bottleneck summary

- Dominated by branching, state expansion, and repeated evaluation logic.
- Less predictable memory/control behavior than numeric kernels.

### Hardware acceleration idea

- State-transition / decision-evaluation accelerator with fast table-style transition support and branch-friendly execution assistance.

---

## Why mdp is the hard one

- More algorithmic/control complexity than serialization or pure numeric loops.
- Optimization requires reasoning about state representation, branching behavior, and transition pruning, not only arithmetic throughput.
- Better for a strong advanced-analysis section in the report.

---

## Suggested next step

- Profile both benchmarks in the same VM environment (nbody and mdp) and capture hotspot evidence (perf + flamegraph) to support optimization and hardware-accelerator claims.

---

## Phase 3: Learn pyperformance Mechanics (nbody + mdp)

Run from repository root:

```bash
cd /root/homewroksbothsofthard
mkdir -p project_results
```

### Step 3.1 - Run a single benchmark

```bash
python3-dbg -m pyperformance run -b nbody -o project_results/nbody_baseline.json
python3-dbg -m pyperformance run -b mdp -o project_results/mdp_baseline.json
```

### Step 3.2 - Compare two runs

After you create optimized runs:

```bash
python3 -m pyperformance compare project_results/nbody_baseline.json project_results/nbody_opt.json
python3 -m pyperformance compare project_results/mdp_baseline.json project_results/mdp_opt.json
```

### Step 3.3 - Understand output

- Focus on mean runtime first.
- Check standard deviation to estimate noise.
- Treat tiny gains as suspect unless repeated runs stay consistent.

---

## Phase 4: Profile with perf + Flame Graph (per benchmark)

Create folders:

```bash
mkdir -p project_results/nbody project_results/mdp
```

### Step 4.1 - Record profiles

```bash
/usr/bin/perf record -F 999 -g -o project_results/nbody/perf.data -- python3-dbg -m pyperformance run -b nbody
/usr/bin/perf record -F 999 -g -o project_results/mdp/perf.data -- python3-dbg -m pyperformance run -b mdp
```

### Step 4.2 - Generate text reports

```bash
/usr/bin/perf report --stdio -i project_results/nbody/perf.data > project_results/nbody/report.txt
/usr/bin/perf report --stdio -i project_results/mdp/perf.data > project_results/mdp/report.txt
```

### Step 4.3 - Generate flame graphs

```bash
/usr/bin/perf script -i project_results/nbody/perf.data > project_results/nbody/out.perf
/opt/FlameGraph/stackcollapse-perf.pl project_results/nbody/out.perf > project_results/nbody/out.folded
/opt/FlameGraph/flamegraph.pl project_results/nbody/out.folded > project_results/nbody/flamegraph_nbody.svg

/usr/bin/perf script -i project_results/mdp/perf.data > project_results/mdp/out.perf
/opt/FlameGraph/stackcollapse-perf.pl project_results/mdp/out.perf > project_results/mdp/out.folded
/opt/FlameGraph/flamegraph.pl project_results/mdp/out.folded > project_results/mdp/flamegraph_mdp.svg
```

---

## Phase 5: Detect Bottlenecks

For each benchmark, extract the top hotspots:

```bash
head -n 80 project_results/nbody/report.txt
head -n 80 project_results/mdp/report.txt
```

Write down:

- Top 2 to 3 widest functions in each flame graph.
- Why each is slow: algorithmic complexity, redundant work, branch-heavy control, or allocation pressure.

---

## Phase 6: Optimize

Create isolated benchmark copies before editing:

```bash
mkdir -p project_results/optimized_src
cp -r /tmp/pyperformance* project_results/optimized_src 2>/dev/null || true
```

Practical optimization targets:

- nbody: reduce redundant arithmetic inside pairwise loop, improve locality, avoid repeated recomputation.
- mdp: cut repeated successor generation, cache transition computations, reduce temporary allocations.

Then rerun:

```bash
python3-dbg -m pyperformance run -b nbody -o project_results/nbody_opt.json
python3-dbg -m pyperformance run -b mdp -o project_results/mdp_opt.json
```

---

## Phase 7: Show Performance Improvement

Run comparisons and save evidence:

```bash
python3 -m pyperformance compare project_results/nbody_baseline.json project_results/nbody_opt.json > project_results/nbody_compare.txt
python3 -m pyperformance compare project_results/mdp_baseline.json project_results/mdp_opt.json > project_results/mdp_compare.txt
```

Report table template:

| Benchmark | Baseline mean | Optimized mean | Improvement |
|---|---:|---:|---:|
| nbody | X ms | Y ms | Z% |
| mdp | X ms | Y ms | Z% |

Target:

- Reach at least 7 percent speedup in at least two benchmark results across nbody and mdp.

---

## Execution note for this VM

- This VM serial console can merge long pasted commands.
- Run one short command at a time and wait for prompt return before sending the next command.
