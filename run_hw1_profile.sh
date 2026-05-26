#!/usr/bin/env bash
set -euo pipefail

# Defaults: large enough to expose CPU/cache behavior while remaining practical.
LENGTH="${1:-4000000}"
ITERS="${2:-50}"
SEED="${3:-123456789}"

CXX="${CXX:-g++}"
CXXFLAGS="-O3 -march=native -std=c++17 -Wall -Wextra"
HW_EVENTS="cycles,instructions,cache-references,cache-misses,branches,branch-misses,task-clock"
SW_EVENTS="task-clock,context-switches,cpu-migrations,page-faults"

run_perf_with_fallback() {
  local out_file="$1"
  shift

  if perf stat -e "$HW_EVENTS" -o "$out_file" "$@" 1>/dev/null 2>&1; then
    if grep -qi "not supported" "$out_file"; then
      echo "Hardware perf events reported as unsupported; retrying with software-only events for $out_file"
      perf stat -e "$SW_EVENTS" -o "$out_file" "$@" 1>/dev/null
      return 0
    fi

    echo "Used hardware+software perf events for $out_file"
    return 0
  fi

  echo "Hardware perf events unavailable; retrying with software-only events for $out_file"
  perf stat -e "$SW_EVENTS" -o "$out_file" "$@" 1>/dev/null
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
/usr/bin/time -f "NAIVE wall=%e sec" ./hw1_naive "$LENGTH" "$ITERS" "$SEED" 1>/dev/null
/usr/bin/time -f "OPT   wall=%e sec" ./hw1_optimized "$LENGTH" "$ITERS" "$SEED" 1>/dev/null

echo "[4/5] perf stat for naive"
run_perf_with_fallback \
  results/perf_naive.txt \
  ./hw1_naive "$LENGTH" "$ITERS" "$SEED"

echo "[5/5] perf stat for optimized"
run_perf_with_fallback \
  results/perf_optimized.txt \
  ./hw1_optimized "$LENGTH" "$ITERS" "$SEED"

echo "Done. Perf reports:"
echo "  results/perf_naive.txt"
echo "  results/perf_optimized.txt"
