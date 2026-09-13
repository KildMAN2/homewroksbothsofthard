# Final Software Result

I compared the correct optimization attempts using the recorded preliminary benchmark results in `subRay/docs/03_optimization.md` and the files under `subRay/results/` and `subRay/optimized/`.

## Preliminary Selection

| Version | Correct | Preliminary Mean | Improvement vs Original |
|---------|---------|------------------|-------------------------|
| Attempt 1 | Yes | 103 ms | 78.18% |
| Attempt 2 | Yes | 242 ms | 48.73% |
| Attempt 3 | Yes | 243 ms | 48.52% |

Selected best correct implementation: Attempt 1.

Reason: it has the lowest preliminary mean among the correct attempts and the largest improvement versus the original preliminary baseline.

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

