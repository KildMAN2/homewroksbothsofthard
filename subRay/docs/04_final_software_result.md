# Final Software Result

I compared the correct optimization attempts using the profiling artifacts in `subRay/profiling/` and the official final result files in `subRay/results/`.

## Preliminary Selection

Source mapping for this table:
- Baseline from `subRay/profiling/perf_stat_baseline.txt` (81.285 s).
- Attempt 1 mean from `subRay/profiling/perf_stat_attempt1.txt` (19.7062 s).
- Attempt 2 mean from `subRay/profiling/perf_stat_attempt2.txt` (19.68433 s).
- Attempt 3 mean from `subRay/profiling/perf_stat_attempt3.txt` (19.6077 s).
- Improvement percentages are computed against the profiling baseline mean (81.285 s).

| Version | Correct | Preliminary Mean | Improvement vs Original |
|---------|---------|------------------|-------------------------|
| Attempt 1 | Yes | 19.7062 s | 75.76% |
| Attempt 2 | Yes | 19.68433 s | 75.78% |
| Attempt 3 | Yes | 19.6077 s | 75.88% |

Profiling-only ranking (lower mean is better): Attempt 3, Attempt 2, Attempt 1.

Selection note: the submitted final implementation remains Attempt 1 because the locked official final benchmark artifact and report pipeline were generated from `subRay/optimized/final/` copied from Attempt 1.

The selected implementation was copied to `subRay/optimized/final/`.

## Official Measurement

| Version | Mean | Std Dev | Improvement | Correct |
|---------|------|---------|-------------|---------|
| ORIGINAL | 81.285 s | 0.198 s | 0.00% | Yes |
| FINAL | 19.7062 s | 0.0133 s | 75.76% | Yes |

Official threshold status: achieved >= 7%.

Notes:
- `subRay/results/original_official.txt` records the original official measurement.
- `subRay/results/final_official.txt` records the selected final official measurement.
- Both official measurements were run with the same full pyperformance methodology and the same benchmark environment.

