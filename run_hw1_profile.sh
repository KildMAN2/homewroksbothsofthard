#!/usr/bin/env bash
set -euo pipefail

# Defaults: large enough to expose CPU/cache behavior while remaining practical.
LENGTH="${1:-4000000}"
ITERS="${2:-50}"
SEED="${3:-123456789}"

CXX="${CXX:-g++}"
CXXFLAGS="-O3 -march=native -std=c++17 -Wall -Wextra"
MIXED_EVENTS="cpu-cycles,instructions,cache-references,cache-misses,branches,branch-misses,cpu-clock,page-faults,minor-faults,major-faults,context-switches,cpu-migrations"
TSC_SW_EVENTS="msr/tsc/,cpu-clock,page-faults,minor-faults,major-faults,context-switches,cpu-migrations"
SW_EVENTS="cpu-clock,page-faults,minor-faults,major-faults,context-switches,cpu-migrations"

run_perf_once() {
  local events="$1"
  local out_file="$2"
  shift 2

  if ! perf stat -B -e "$events" -o "$out_file" "$@" 1>/dev/null 2>&1; then
    return 1
  fi

  if grep -Eqi "not supported|unknown event|<not supported>|No permission|not counted|invalid|Cannot find PMU" "$out_file"; then
    return 2
  fi

  return 0
}

run_perf_with_fallback() {
  local out_file="$1"
  shift

  if run_perf_once "$MIXED_EVENTS" "$out_file" "$@"; then
    echo "Used mixed hardware+software perf events for $out_file"
    return 0
  fi
  echo "Hardware PMU unavailable; trying TSC+software events for $out_file"
  if run_perf_once "$TSC_SW_EVENTS" "$out_file" "$@"; then
    echo "Used TSC+software perf events for $out_file"
    return 0
  fi
  echo "TSC unavailable; retrying with software-only events for $out_file"
  if ! perf stat -e "$SW_EVENTS" -o "$out_file" "$@" 1>/dev/null 2>&1; then
    echo "perf stat unavailable on this kernel; recording wall-clock time only for $out_file"
    /usr/bin/time -v "$@" 2>"$out_file" || \
      { /usr/bin/time -f "wall=%e sec\nmax_rss_kb=%M" "$@" 2>"$out_file" || true; }
  fi
}

echo "[1/5] Building binaries"
$CXX $CXXFLAGS hw1_naive.cpp -o hw1_naive
$CXX $CXXFLAGS hw1_optimized.cpp -o hw1_optimized

echo "[2/5] Running correctness check"
NAIVE_OUT="$(./hw1_naive "$LENGTH" "$ITERS" "$SEED")"
OPT_OUT="$(./hw1_optimized "$LENGTH" "$ITERS" "$SEED")"

echo "$NAIVE_OUT"
echo "$OPT_OUT"

NAIVE_SUM="$(echo "$NAIVE_OUT" | awk -F'checksum=' '/RESULT/{print $2}' | awk '{print $1}')"
OPT_SUM="$(echo "$OPT_OUT" | awk -F'checksum=' '/RESULT/{print $2}' | awk '{print $1}')"

if [[ "$NAIVE_SUM" != "$OPT_SUM" ]]; then
  echo "ERROR: checksum mismatch (naive=$NAIVE_SUM optimized=$OPT_SUM)"
  exit 2
fi

echo "Checksums match: $NAIVE_SUM"

mkdir -p results

echo "[3/5] Timing (wall clock)"
NAIVE_WALL=$( { /usr/bin/time -f "%e" ./hw1_naive "$LENGTH" "$ITERS" "$SEED" > /dev/null; } 2>&1 )
OPT_WALL=$( { /usr/bin/time -f "%e" ./hw1_optimized "$LENGTH" "$ITERS" "$SEED" > /dev/null; } 2>&1 )
echo "NAIVE wall=${NAIVE_WALL} sec"
echo "OPT   wall=${OPT_WALL} sec"

echo "[4/5] perf stat for naive"
run_perf_with_fallback \
  results/perf_naive.txt \
  ./hw1_naive "$LENGTH" "$ITERS" "$SEED"
cat results/perf_naive.txt

echo "[5/5] perf stat for optimized"
run_perf_with_fallback \
  results/perf_optimized.txt \
  ./hw1_optimized "$LENGTH" "$ITERS" "$SEED"
cat results/perf_optimized.txt

SPEEDUP=$(awk "BEGIN { printf \"%.2fx\", ${NAIVE_WALL} / ${OPT_WALL} }" 2>/dev/null || echo "N/A")

{
  printf "# HW1 Run Summary\n# %s\n# length=%s  iters=%s  seed=%s\n\n" \
    "$(date)" "$LENGTH" "$ITERS" "$SEED"
  printf "=== Correctness ===\n%s\n%s\nChecksums match: %s\n\n" \
    "$NAIVE_OUT" "$OPT_OUT" "$NAIVE_SUM"
  printf "=== Wall-clock Timing ===\nNAIVE   %s sec\nOPT     %s sec\nSpeedup %s\n\n" \
    "$NAIVE_WALL" "$OPT_WALL" "$SPEEDUP"
  printf "=== perf_naive.txt ===\n"
  cat results/perf_naive.txt
  printf "\n=== perf_optimized.txt ===\n"
  cat results/perf_optimized.txt
} > results/summary.txt

echo "Done. Results saved:"
echo "  results/perf_naive.txt"
echo "  results/perf_optimized.txt"
echo "  results/summary.txt"
