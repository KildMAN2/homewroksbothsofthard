#!/usr/bin/env bash
set -euo pipefail

# Run inside the Linux guest after PMU-capable boot.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# Sanity check: PMU-backed hardware counters must be visible.
if perf stat -e cycles,instructions,branches,branch-misses -- sleep 1 2>&1 | grep -qi "not supported"; then
  echo "ERROR: PMU counters are still unavailable in this environment." >&2
  exit 2
fi

PROFILE_USE_FAST=0 RUNS=3 PROFILE_TARGET=attempt1 scripts/run_profile.sh
PROFILE_USE_FAST=0 RUNS=3 PROFILE_TARGET=attempt2 scripts/run_profile.sh
PROFILE_USE_FAST=0 RUNS=3 PROFILE_TARGET=attempt3 scripts/run_profile.sh

echo "Done. Files generated under subRay/profiling/:"
echo "  perf_stat_attempt1.txt"
echo "  perf_stat_attempt2.txt"
echo "  perf_stat_attempt3.txt"
