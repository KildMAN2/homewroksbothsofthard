# Nbody Hardware/Software Optimization Project Log

## Purpose
This document is the single source of truth for the Nbody workstream from this point forward. It records what was executed, why each action was taken, what changed, technical interpretation of results, and decisions for both software and hardware acceleration.

This log is intentionally explanatory rather than a raw terminal dump so it can be reused directly for presentation preparation.

## Scope Rules
- Benchmark code is not modified in this step.
- Every important step must append:
  - command(s)
  - reason
  - changed files
  - technical meaning of outcomes
- Keep conclusions evidence-based and tie claims to measured data.

## Current Status
### Completed
- Created this tracking file.
- Defined end-to-end execution plan from current state to final submission.
- Preserved benchmark code unchanged for now.
- Inspected original Nbody source file in VM and documented algorithm details.
- Created V1 scalarized benchmark copy without modifying original source.
- Created and executed a short VM correctness test for V1.
- Created V2 unrolled benchmark copy from V1 and verified correctness in VM.

### Remaining
- Run and complete mdp benchmark artifacts (baseline, optimized placeholder run, compare, perf profile, flamegraph).
- Review nbody and mdp result quality, especially variance and significance.
- Implement staged Nbody optimization variants (V1-V5) in an isolated optimized benchmark copy.
- Run correctness checks before long benchmark runs.
- Re-run benchmark measurements for optimized variants.
- Compare baseline vs optimized for each version step and final version.
- Capture optimized profiling + before/after flamegraph interpretation.
- Refine Nbody accelerator architecture notes and align SystemVerilog behavior with intended math and pipeline timing.
- Produce final report consistency pass (numbers, claims, significance language).
- Final commit and push.

## End-to-End Plan From This Step
1. Stabilize measurement setup
- Goal: reduce noise and make comparison defensible.
- Actions: pin environment, avoid background load, optionally use pyperf tuning guidance.

2. Establish reproducible baselines
- Goal: ensure baseline JSON and perf artifacts are valid and traceable.
- Actions: verify existing nbody artifacts and complete missing mdp artifacts.

3. Build optimization ladder (Nbody)
- Goal: isolate contribution of each change.
- Versions:
  - V0 original
  - V1 scalar local variables
  - V2 unrolled fixed body pairs
  - V3 sqrt-based inverse-distance expression
  - V4 precomputed dt*mass constants
  - V5 combined pure-Python path

4. Correctness gate before expensive benchmarking
- Goal: prevent invalid speedups caused by numerical or logic drift.
- Actions: compare physical invariants/outputs within tolerance, confirm no NaN/Inf, verify deterministic behavior under repeated short runs.

5. Full performance evaluation
- Goal: collect statistically meaningful performance evidence.
- Actions: run pyperformance for baseline and optimized variants, compare outputs, interpret significance.

6. Profiling analysis and flamegraph narrative
- Goal: explain where time moved and why.
- Actions: capture perf for optimized run(s), generate flamegraphs, compare before vs after hotspot widths and call-path composition.

7. Hardware acceleration refinement
- Goal: align hardware proposal with true Nbody math and cycle-accurate flow.
- Actions: confirm 1/r^3 datapath, stage alignment with valid propagation, I/O contract, software interface, expected frequency and trade-offs.

8. Final packaging
- Goal: ensure submission quality.
- Actions: synchronize report text with measured results, ensure scripts are reproducible, finalize README and presentation notes.

## Original Nbody Benchmark

Source inspected:
- /opt/pyperformance/pyperformance/data-files/benchmarks/bm_nbody/run_benchmark.py

### Body representation

Each body is represented as a 3-tuple:

```python
([x, y, z], [vx, vy, vz], mass)
```

- Position is a mutable list of 3 floats.
- Velocity is a mutable list of 3 floats.
- Mass is a scalar float.

All five bodies are stored in `BODIES` and then flattened to:

```python
SYSTEM = list(BODIES.values())
```

### The 10 body pairs

The benchmark precomputes unique unordered body pairs once:

```python
PAIRS = combinations(SYSTEM)
```

With 5 bodies, pair count is:

$$
\binom{5}{2} = 10
$$

The 10 interactions are conceptually:

- 0-1, 0-2, 0-3, 0-4
- 1-2, 1-3, 1-4
- 2-3, 2-4
- 3-4

This avoids duplicate pair computation and avoids self-interactions.

### `advance(dt, n, bodies=SYSTEM, pairs=PAIRS)`

This is the simulation hot path. For each of `n` timesteps:

1. Iterate all body pairs.
2. Compute displacement vector:

```python
dx = x1 - x2
dy = y1 - y2
dz = z1 - z2
```

3. Compute force scale factor:

```python
mag = dt * ((dx*dx + dy*dy + dz*dz) ** (-1.5))
```

Equivalent formula:

$$
	ext{mag} = dt \cdot \frac{1}{(r^2)^{3/2}} = dt \cdot \frac{1}{r^3}
$$

where:

$$
r^2 = dx^2 + dy^2 + dz^2
$$

4. Scale by masses and update velocities for both bodies (equal and opposite effect):

```python
b1m = m1 * mag
b2m = m2 * mag
v1[0] -= dx * b2m
...
v2[0] += dx * b1m
...
```

5. After all pair forces are applied, update each body position:

```python
r[0] += dt * vx
r[1] += dt * vy
r[2] += dt * vz
```

### `report_energy(bodies=SYSTEM, pairs=PAIRS, e=0.0)`

Computes total system energy as potential + kinetic.

Potential term over pairs:

```python
e -= (m1 * m2) / sqrt(dx*dx + dy*dy + dz*dz)
```

Kinetic term over bodies:

```python
e += m * (vx*vx + vy*vy + vz*vz) / 2.0
```

Mathematically:

$$
E = \sum_i \frac{1}{2}m_i\|v_i\|^2 - \sum_{i<j}\frac{m_i m_j}{r_{ij}}
$$

The benchmark calls this before and after `advance()` to validate physical consistency and prevent dead-code elimination.

### `offset_momentum(ref, bodies=SYSTEM, px=0.0, py=0.0, pz=0.0)`

Computes total momentum of all bodies and adjusts one reference body (default sun) so net momentum becomes zero.

Core logic:

```python
px -= vx * m
py -= vy * m
pz -= vz * m
v_ref[0] = px / m_ref
v_ref[1] = py / m_ref
v_ref[2] = pz / m_ref
```

This establishes a centered inertial frame and prevents artificial drift in long simulations.

### Operations inside the hot loop

Inside the pairwise inner loop, the expensive repeated operations are:

- Float subtract/multiply/add for `dx, dy, dz, d2`.
- Power operation `** (-1.5)`.
- Per-pair list index reads and writes to velocity vectors.
- Mass scaling multiplications (`m1 * mag`, `m2 * mag`).

These operations map directly to profiling hotspots such as Python arithmetic dispatch and float/list object handling.

### Invariant values (important for optimization)

Values that do not change during one `advance()` call:

- `dt`
- Masses (`m1`, `m2`, ...)
- Pair topology (`PAIRS` contents/order)
- Body count (always 5 in this benchmark setup)

Values that do change each iteration:

- Positions `[x, y, z]`
- Velocities `[vx, vy, vz]`
- Pairwise distances and force magnitudes

Optimization implication:

- Good candidates for precomputation are terms involving only constants/invariants.
- Hot-loop savings are most likely from reducing Python indexing/object churn and expensive scalar ops.

## Baseline and Profiling

Artifacts reviewed under `project_results/nbody/`:

- `baseline.json` (6,696 bytes)
- `report.txt` (3,517,079 bytes)
- `perf.data` (26,113,520 bytes)
- `out.perf` (63,641,468 bytes)
- `out.folded` (340,803 bytes)
- `flamegraph_nbody.svg` (131,908 bytes)
- `compare.txt` (635 bytes)

### Baseline timing and comparison interpretation

From `compare.txt`:

- Baseline: `5.30 sec +- 1.37 sec`
- Comparison run: `5.09 sec +- 0.32 sec`
- Reported ratio: `1.04x faster`
- Statistical verdict: `Not significant`

Important interpretation:

- This must not be presented as a confirmed optimization win.
- The run indicates a possible directional improvement, but significance was not established.
- Because benchmark code path may be unchanged between runs, the observed delta can be caused by runtime noise.

### Instability warning meaning

The benchmark execution emitted instability warnings in the run logs. Even without those console lines, the statistics already support that interpretation:

- Standard deviation of `1.37 sec` on mean `5.30 sec` is high variance.
- The tool-level verdict `Not significant` confirms low confidence in declaring a real speedup.

Conclusion:

- Current baseline evidence is suitable for hotspot analysis.
- Current baseline-vs-second-run timing is not sufficient to claim a validated optimization result.

### Important `perf` hotspots (`report.txt`)

Top observations from the perf report:

- `_PyEval_EvalFrameDefault`: about `30.53%` self time.
- A large `[unknown]` dispatch region (~`27.11%` children) fans into Python arithmetic and object operations.
- `binary_op1`: about `5.60%` self.
- `PyFloat_FromDouble`: about `6.43%` self (plus additional child appearances).
- `float_mul.lto_priv.0`: about `2.36%` self.
- `list_subscript.lto_priv.0`: about `1.97%` self.
- `PyObject_SetItem`: about `1.78%` self.
- `PyObject_GetItem`: about `1.76%` self.
- `__ieee754_pow_sse2`: about `1.65%` self.

Meaning:

- The benchmark is heavily limited by Python interpreter and object-model overhead in the hot loop.
- Numeric math is expensive, but Python-level dispatch/indexing/object creation is a first-order cost component.
- This supports optimization efforts aimed at reducing list indexing and temporary float churn before attempting aggressive native rewrites.

### Role of each profiling file

- `perf.data`: raw sampled profile captured by `perf record`.
- `out.perf`: text event stream from `perf script`.
- `out.folded`: collapsed stack format for flamegraph generation.
- `flamegraph_nbody.svg`: visual aggregate where box width encodes cumulative time.

### Flame graph meaning (`flamegraph_nbody.svg`)

What the graph communicates:

- Wider stacks correspond to more total time spent in those call paths.
- Large interpreter-related region (`_PyEval_EvalFrameDefault`) confirms substantial Python dispatch overhead.
- Visible frames for `binary_op1`, `PyFloat_FromDouble`, `list_subscript`, and `pow`-related functions confirm hot-loop mix of arithmetic and object/indexing work.

What we can conclude safely:

- Flamegraph and perf are consistent with each other.
- Hotspots align with the original algorithm structure (`advance()` pair loop with repeated scalar ops and list updates).

What we should not conclude yet:

- We should not claim the `5.30 sec -> 5.09 sec` change as a true optimization outcome until code differences and statistical significance are both confirmed.

## V1 Scalarization Implementation and Correctness

### What changed

Created a new file:

- `bm_nbody/run_benchmark_v1_scalar.py`

The original benchmark file in `/opt/pyperformance/pyperformance/data-files/benchmarks/bm_nbody/run_benchmark.py` was not modified.

V1 change scope:

- Scalarized velocity list reads into local variables inside the pair loop.
- Performed arithmetic updates on local scalars.
- Wrote results back to velocity lists once per pair interaction.
- Scalarized position/velocity reads in the position-update loop to reduce repeated list indexing.
- Preserved original equations, pair ordering, and outer loop structure.

Also created:

- `bm_nbody/test_v1_correctness.py`

This test compares V1 against a reference implementation of the original algorithm over a short run.

### Why scalarization may improve performance

The original hot loop repeatedly performs Python list indexing and assignment operations (`v1[0]`, `v1[1]`, `v1[2]`, etc.) for every body-pair interaction.

Scalarization can help because:

- Local variable access is cheaper than repeated list element access.
- Fewer list get/set operations reduce Python object-model overhead.
- Arithmetic on local scalars can reduce interpreter dispatch pressure in tight loops.

Expected effect:

- Same physics and algorithm behavior, lower overhead around bookkeeping operations.

### Short correctness test result (VM)

Executed only a short correctness test (not full pyperformance benchmark):

- Steps: `100`
- `energy_before_original` == `energy_before_v1`
- `energy_after_original` == `energy_after_v1`
- `abs_energy_before_diff = 0.000e+00`
- `abs_energy_after_diff = 0.000e+00`
- `max_state_abs_diff = 0.000e+00`
- Tolerance: `1e-12`
- Final verdict: `CORRECTNESS_CHECK=PASS`

Interpretation:

- For the tested short run, V1 is numerically equivalent to the reference implementation within strict tolerance.
- This is sufficient to proceed to performance benchmarking in later steps.

## V2 Unrolled Pair Loop Implementation and Correctness

### What loop was removed

In V1/original-style `advance()`, each timestep uses a generic inner loop:

```python
for (([x1, y1, z1], v1, m1), ([x2, y2, z2], v2, m2)) in pairs:
  ...
```

In V2, this loop is removed and replaced by explicit code blocks for exactly 10 interactions in the original order:

- 0-1, 0-2, 0-3, 0-4, 1-2, 1-3, 1-4, 2-3, 2-4, 3-4

This preserves the original interaction sequence and physics update ordering.

### Why loop unrolling can help in Python

Loop unrolling can reduce interpreter overhead by removing repeated per-iteration costs inside the hottest loop:

- iterator advancement
- tuple unpacking for each pair
- loop-control branch overhead

By using explicit pair blocks, more execution time is spent in arithmetic work and less in Python loop mechanics.

### Possible disadvantages

Unrolling in Python has trade-offs:

- Larger source code size and lower readability.
- Higher maintenance burden (manual edits are error-prone).
- Greater risk of copy/paste mistakes if equations diverge between blocks.
- Potential instruction-cache pressure from larger function bodies.

So V2 can improve speed, but it increases code complexity and review burden.

### Correctness result (short VM test)

Executed short correctness test only (not full benchmark):

- Test script: `bm_nbody/test_v2_correctness.py`
- Steps: `100`
- `energy_before_original` == `energy_before_v2`
- `energy_after_original` == `energy_after_v2`
- `abs_energy_before_diff = 0.000e+00`
- `abs_energy_after_diff = 0.000e+00`
- `max_state_abs_diff = 0.000e+00`
- Tolerance: `1e-12`
- Final verdict: `CORRECTNESS_CHECK=PASS`

Interpretation:

- V2 preserved numerical behavior exactly in this short equivalence run.
- This clears V2 for later timing measurements.

## Step Log

### Step 0 - Documentation Bootstrap (Current Step)
Date: 2026-09-10

Command(s) run:
- file existence check for docs/nbody_project.md
- workspace listing to confirm repository root layout

Why this was run:
- To ensure the required documentation file did not already exist and avoid accidental overwrite.
- To place the new file in the correct repository path.

File(s) changed:
- docs/nbody_project.md (created)

What changed in code:
- No benchmark or source code was modified.
- Only documentation scaffolding was added.

Measured results:
- Not applicable in this step.

Profiling findings:
- Not applicable in this step.

Optimization reasoning:
- Establish traceability first so every future optimization is justified and explainable.

Correctness results:
- Not applicable in this step.

Hardware architecture decisions:
- Deferred to later steps; no hardware source edits in this step.

SystemVerilog implementation decisions:
- Deferred to later steps; no RTL changes in this step.

Problems encountered and fixes:
- No blocking issues in this step.

### Step 1 - Inspect Original Nbody Source (No Code Changes)
Date: 2026-09-10

Command(s) run:
- cd /opt
- cd pyperformance/pyperformance/data-files/benchmarks/bm_nbody
- sed -n '1,260p' run_benchmark.py

Why this was run:
- To extract exact algorithm details from the original benchmark implementation before any optimization work.
- To ensure documentation reflects real source behavior, not assumptions.

File(s) changed:
- docs/nbody_project.md

What changed in code:
- No benchmark/source code changes.
- Added a technical breakdown of representation, equations, hot loop operations, and invariants.

Measured results:
- No new timing/perf run was executed in this step.

Profiling findings:
- No new profile captured in this step; this step supports interpretation of existing profile evidence.

Optimization reasoning:
- Identified invariants and high-frequency operations to guide staged optimization safely.

Correctness results:
- Not applicable in this step.

Hardware architecture decisions:
- Confirmed that any force-acceleration datapath must compute inverse-cube distance behavior.

SystemVerilog implementation decisions:
- No RTL edits in this step.

Problems encountered and fixes:
- VM serial console occasionally truncated long commands.
- Mitigation used: short directory-change commands and a single bounded `sed` read.

Next step:
- Prepare an explicit correctness test plan for V1-V5 optimization stages before long benchmark reruns.

### Step 2 - Baseline Artifact Review and Profiling Interpretation
Date: 2026-09-10

Command(s) run:
- list directory: `project_results/nbody`
- read `project_results/nbody/compare.txt`
- read `project_results/nbody/report.txt`
- list file sizes/timestamps for `project_results/nbody/*`
- search key symbols in `flamegraph_nbody.svg`
- search key symbols in `out.folded`

Why this was run:
- To produce an evidence-based baseline and profiling section using existing artifacts.
- To avoid over-claiming optimization from statistically weak comparison output.

File(s) changed:
- docs/nbody_project.md

What changed in code:
- No benchmark/source code changes.
- Added analysis narrative for timing, instability, perf hotspots, and flamegraph interpretation.

Measured results:
- Baseline/compare numbers extracted and documented from `compare.txt`.

Profiling findings:
- Confirmed dominant interpreter and Python object operation hotspots.

Optimization reasoning:
- Reinforced that first optimizations should target Python-level overhead in the pairwise hot loop.

Correctness results:
- No new correctness run in this step.

Hardware architecture decisions:
- No new architecture decision in this step.

SystemVerilog implementation decisions:
- No RTL changes in this step.

Problems encountered and fixes:
- None blocking during local artifact review.

Next step:
- Define and run correctness gate tests before implementing V1-V5 source changes.

### Step 3 - Implement V1 Scalar Copy and Run VM Correctness Test
Date: 2026-09-10

Command(s) run:
- Local repo:
  - create directory `bm_nbody/`
  - create `bm_nbody/run_benchmark_v1_scalar.py`
  - create `bm_nbody/test_v1_correctness.py`
  - `git add bm_nbody/run_benchmark_v1_scalar.py bm_nbody/test_v1_correctness.py docs/nbody_project.md`
  - `git commit -m "Add nbody V1 scalar copy and short correctness test"`
  - `git push origin master`
- VM repo:
  - `cd /root/homewroksbothsofthard`
  - `git pull --rebase origin master`
  - `python3 bm_nbody/test_v1_correctness.py`

Why this was run:
- To implement the first optimization stage (V1) without touching the original benchmark.
- To verify numerical equivalence with a short correctness gate before any long performance run.

File(s) changed:
- bm_nbody/run_benchmark_v1_scalar.py
- bm_nbody/test_v1_correctness.py
- docs/nbody_project.md

What changed in code:
- Added V1 scalarized copy of benchmark logic.
- Added a standalone correctness harness that checks energy and full state deltas against a reference implementation.

Measured results:
- Correctness run executed in VM with 100 steps.
- All compared deltas were exactly zero within tolerance.

Profiling findings:
- No new perf profile in this step.

Optimization reasoning:
- V1 targets Python list indexing overhead seen in baseline hotspot evidence.

Correctness results:
- PASS (`CORRECTNESS_CHECK=PASS`).

Hardware architecture decisions:
- No hardware changes in this step.

SystemVerilog implementation decisions:
- No RTL changes in this step.

Problems encountered and fixes:
- No blocking issues in this step.

Next step:
- Run short timing checks for V1 vs baseline, then schedule full benchmark runs only after confirming stable execution behavior.

### Step 4 - Implement V2 Unrolled Pairs and Run VM Correctness Test
Date: 2026-09-10

Command(s) run:
- Local repo:
  - create `bm_nbody/run_benchmark_v2_unroll.py`
  - create `bm_nbody/test_v2_correctness.py`
  - `git add bm_nbody/run_benchmark_v2_unroll.py bm_nbody/test_v2_correctness.py`
  - `git commit -m "Add nbody V2 unrolled pair implementation and correctness test"`
  - `git push origin master`
- VM repo:
  - `cd /root/homewroksbothsofthard`
  - `git pull --rebase origin master`
  - `python3 bm_nbody/test_v2_correctness.py`

Why this was run:
- To remove the generic pair loop while preserving original interaction order.
- To verify unrolling did not change numerical behavior before any long performance run.

File(s) changed:
- bm_nbody/run_benchmark_v2_unroll.py
- bm_nbody/test_v2_correctness.py
- docs/nbody_project.md

What changed in code:
- Replaced dynamic pair iteration with explicit 10-pair update blocks.
- Kept scalarized local variable style from V1.
- Kept original formulas and pair update order.

Measured results:
- Short correctness test executed in VM, 100 steps.
- Energy and state diffs were exactly zero at tolerance 1e-12.

Profiling findings:
- No new profiling run in this step.

Optimization reasoning:
- V2 targets Python loop/tuple-unpacking overhead in the hot interaction path.

Correctness results:
- PASS (`CORRECTNESS_CHECK=PASS`).

Hardware architecture decisions:
- No hardware changes in this step.

SystemVerilog implementation decisions:
- No RTL changes in this step.

Problems encountered and fixes:
- Local quick test was canceled by user, so verification was completed directly in VM.

Next step:
- Run short timing checks for V2 vs V1 (still not full benchmark), then continue staged optimization flow.

### Step 5 - Implement V3 Sqrt Formula and Run VM Correctness Test
Date: 2026-09-10

Command(s) run:
- Local repo:
  - create `bm_nbody/run_benchmark_v3_sqrt.py`
  - create `bm_nbody/test_v3_correctness.py`
  - `git add bm_nbody/run_benchmark_v3_sqrt.py bm_nbody/test_v3_correctness.py`
  - `git commit -m "Add nbody V3 sqrt-form implementation and correctness test"`
  - `git push origin master`
  - fix import corruption in V3 file
  - `git commit -m "Fix V3 import syntax regression"`
  - `git push origin master`
  - fix literal backtick-newline corruption across all V3 pair blocks
  - `git commit -m "Fix V3 newline corruption in magnitude computation"`
  - `git push origin master`
- VM repo:
  - `cd /root/homewroksbothsofthard`
  - `git pull --rebase origin master`
  - `python3 bm_nbody/test_v3_correctness.py`

Why this was run:
- To apply the V3 arithmetic rewrite from power-form inverse-distance to sqrt-based inverse-distance while keeping V2 interaction order.
- To verify numerical equivalence in VM before any longer benchmark runs.

File(s) changed:
- bm_nbody/run_benchmark_v3_sqrt.py
- bm_nbody/test_v3_correctness.py
- docs/nbody_project.md

What changed in code:
- Added V3 benchmark variant derived from V2 unrolled form.
- Replaced `d2 ** (-1.5)` with `1.0 / (d2 * math.sqrt(d2))` in all 10 pair blocks.
- Added V3 short correctness harness against reference implementation.

Measured results:
- VM correctness test (100 steps):
  - `abs_energy_before_diff = 0.000e+00`
  - `abs_energy_after_diff = 0.000e+00`
  - `max_state_abs_diff = 5.551e-17`
  - tolerance `1e-12`
  - verdict `CORRECTNESS_CHECK=PASS`

Profiling findings:
- No new profiling run in this step.

Optimization reasoning:
- V3 removes exponentiation in the hot loop and uses explicit sqrt-based inverse-cube computation.
- This can reduce overhead from generic power handling while preserving equivalent math in floating-point.

Correctness results:
- PASS (`CORRECTNESS_CHECK=PASS`).

Hardware architecture decisions:
- No hardware changes in this step.

SystemVerilog implementation decisions:
- No RTL changes in this step.

Problems encountered and fixes:
- First VM run failed due to malformed text inserted during local replacement (`import pyperf` line corruption).
- Second VM run failed due to literal backtick-newline text embedded in 10 V3 pair blocks.
- Both syntax regressions were fixed and re-pushed before final VM correctness rerun.

Next step:
- Build V4 precompute variant from V3, run short VM correctness test, then proceed to final combined variant.

## Commands Used
Important command history is appended here in chronological order.

1. file_search docs/nbody_project.md
- Purpose: check whether the target documentation file already exists.

2. list_dir repository root
- Purpose: verify workspace structure before creating docs file.

3. cd /opt
- Purpose: navigate to VM installation root for benchmark source inspection.

4. cd pyperformance/pyperformance/data-files/benchmarks/bm_nbody
- Purpose: open the exact benchmark directory requested by the task.

5. sed -n '1,260p' run_benchmark.py
- Purpose: read original Nbody implementation without modifying code.

6. list_dir project_results/nbody
- Purpose: confirm required artifact set exists.

7. read_file project_results/nbody/compare.txt
- Purpose: extract baseline/comparison timing and significance verdict.

8. read_file project_results/nbody/report.txt
- Purpose: extract top perf hotspots and percentages.

9. Get-ChildItem project_results/nbody | Select-Object Name,Length,LastWriteTime
- Purpose: capture artifact sizes and timestamps for traceable evidence.

10. grep_search on flamegraph_nbody.svg for key symbols
- Purpose: verify hotspot functions are visible in flamegraph output.

11. grep_search on out.folded for key symbols
- Purpose: verify collapsed-stack evidence aligns with perf/flamegraph findings.

12. create directory bm_nbody
- Purpose: prepare isolated location for optimization variants and tests.

13. create file bm_nbody/run_benchmark_v1_scalar.py
- Purpose: implement V1 scalarized benchmark copy while leaving original benchmark unchanged.

14. create file bm_nbody/test_v1_correctness.py
- Purpose: add short correctness gate before expensive benchmark runs.

15. git add bm_nbody/run_benchmark_v1_scalar.py bm_nbody/test_v1_correctness.py docs/nbody_project.md
- Purpose: stage V1 implementation and documentation.

16. git commit -m "Add nbody V1 scalar copy and short correctness test"
- Purpose: create traceable checkpoint for V1 work.

17. git push origin master
- Purpose: publish V1 files so VM can run the same version.

18. cd /root/homewroksbothsofthard
- Purpose: navigate VM clone before updating from GitHub.

19. git pull --rebase origin master
- Purpose: sync VM with latest pushed V1 files.

20. python3 bm_nbody/test_v1_correctness.py
- Purpose: execute short numerical equivalence test in VM.

21. create file bm_nbody/run_benchmark_v2_unroll.py
- Purpose: implement V2 loop-unrolled pair updates while preserving original interaction order.

22. create file bm_nbody/test_v2_correctness.py
- Purpose: validate V2 numerical equivalence using a short run.

23. git add bm_nbody/run_benchmark_v2_unroll.py bm_nbody/test_v2_correctness.py
- Purpose: stage V2 implementation and test.

24. git commit -m "Add nbody V2 unrolled pair implementation and correctness test"
- Purpose: checkpoint V2 work for traceability.

25. git push origin master
- Purpose: publish V2 files so VM can execute the same code.

26. cd /root/homewroksbothsofthard
- Purpose: navigate to VM clone before syncing.

27. git pull --rebase origin master
- Purpose: sync VM with latest V2 changes.

28. python3 bm_nbody/test_v2_correctness.py
- Purpose: execute short V2 correctness gate in VM.

29. git add bm_nbody/run_benchmark_v3_sqrt.py bm_nbody/test_v3_correctness.py
- Purpose: stage V3 implementation and test.

30. git commit -m "Add nbody V3 sqrt-form implementation and correctness test"
- Purpose: checkpoint initial V3 work for traceability.

31. git push origin master
- Purpose: publish V3 files so VM can execute the same code.

32. git pull --rebase origin master (VM)
- Purpose: sync VM with latest V3 files.

33. python3 bm_nbody/test_v3_correctness.py (VM)
- Purpose: run V3 correctness gate in VM.

34. git commit -m "Fix V3 import syntax regression"
- Purpose: fix malformed import text discovered by VM execution.

35. git commit -m "Fix V3 newline corruption in magnitude computation"
- Purpose: fix literal backtick-newline corruption in V3 force-magnitude lines.

36. git push origin master
- Purpose: publish V3 syntax fixes for final VM validation.

37. git pull --rebase origin master (VM)
- Purpose: sync VM with V3 syntax-fix commits.

38. python3 bm_nbody/test_v3_correctness.py (VM)
- Purpose: confirm final V3 correctness after fixes.

## Evidence Pointers
- Nbody compare artifact: project_results/nbody/compare.txt
- Nbody perf text report: project_results/nbody/report.txt
- Nbody flamegraph: project_results/nbody/flamegraph_nbody.svg
- Existing benchmark scripts: project_results/script_nbody.sh and project_results/script_mdp.sh

## Update Protocol For Future Steps
For each important action, append one new "Step N" entry with:
- command(s)
- rationale
- changed files
- technical explanation of outputs
- decision taken
- next step

This guarantees that the final report and presentation can be built directly from this file.
