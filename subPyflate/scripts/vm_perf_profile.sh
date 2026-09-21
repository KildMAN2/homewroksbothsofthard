#!/usr/bin/env bash
# vm_perf_profile.sh
# Runs perf stat + perf record for baseline and final inside the CS-lab QEMU VM.
# Meant to be executed from subPyflate/ inside the guest (KVM) so that hardware
# PMU counters are available.
#
# Usage (inside guest, from subPyflate/):
#   bash scripts/vm_perf_profile.sh
#
# Writes into subPyflate/profiling/:
#   vm_perf_stat_baseline.txt   vm_perf_stat_final.txt
#   vm_perf_baseline.data       vm_perf_final.data
#   vm_perf_report_baseline.txt vm_perf_report_final.txt
#
# All output has the vm_ prefix so it never overwrites the earlier Windows-TCG
# artifacts under the same profiling/ directory.

set -eu
cd "$(dirname "${BASH_SOURCE[0]}")/.."   # anchor at subPyflate/
mkdir -p profiling

PERF_EVENTS="cycles,instructions,branches,branch-misses,cache-references,cache-misses,page-faults,context-switches,task-clock,cpu-clock"

echo "[vm_perf] ================================================"
echo "[vm_perf] Baseline: perf stat -r 3 (fast pyperformance)"
echo "[vm_perf] ================================================"
perf stat -r 3 -e "$PERF_EVENTS" \
    -o profiling/vm_perf_stat_baseline.txt \
    -- python3-dbg -m pyperformance run --bench pyflate --fast

echo "[vm_perf] ================================================"
echo "[vm_perf] Baseline: perf record + perf report"
echo "[vm_perf] ================================================"
perf record -F 999 -g -o profiling/vm_perf_baseline.data \
    -- python3-dbg -m pyperformance run --bench pyflate --fast
perf report --stdio -i profiling/vm_perf_baseline.data \
    > profiling/vm_perf_report_baseline.txt 2>/dev/null

echo "[vm_perf] ================================================"
echo "[vm_perf] Final: perf stat -r 3 (fast pyperformance)"
echo "[vm_perf] ================================================"
perf stat -r 3 -e "$PERF_EVENTS" \
    -o profiling/vm_perf_stat_final.txt \
    -- python3-dbg -m pyperformance run --manifest optimized/final/MANIFEST --bench pyflate_final --fast

echo "[vm_perf] ================================================"
echo "[vm_perf] Final: perf record + perf report"
echo "[vm_perf] ================================================"
perf record -F 999 -g -o profiling/vm_perf_final.data \
    -- python3-dbg -m pyperformance run --manifest optimized/final/MANIFEST --bench pyflate_final --fast
perf report --stdio -i profiling/vm_perf_final.data \
    > profiling/vm_perf_report_final.txt 2>/dev/null

echo "[vm_perf] ================================================"
echo "[vm_perf] ALL DONE"
echo "[vm_perf] ================================================"
echo ""
echo "--- Baseline perf stat (first 25 lines) ---"
head -25 profiling/vm_perf_stat_baseline.txt || true
echo ""
echo "--- Final perf stat (first 25 lines) ---"
head -25 profiling/vm_perf_stat_final.txt || true
echo ""
echo "--- Files created ---"
ls -la profiling/vm_perf_*
