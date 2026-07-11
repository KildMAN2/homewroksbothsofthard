#!/usr/bin/env bash
set -euo pipefail

ZIP_NAME="${1:-hw1_submission.zip}"

FILES=(
  hw1_naive.cpp
  hw1_optimized.cpp
  run_hw1_profile.sh
  HW1_REPORT_FINAL.md
  SUBMITTERS.md
  ai_prompts_used.txt
  results/perf_naive.txt
  results/perf_optimized.txt
  results/summary.txt
)

for f in "${FILES[@]}"; do
  if [[ ! -f "$f" ]]; then
    echo "Missing required file: $f"
    exit 1
  fi
done

zip -r "$ZIP_NAME" "${FILES[@]}"
echo "Created $ZIP_NAME"
