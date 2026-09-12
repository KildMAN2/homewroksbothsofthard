#!/usr/bin/env bash
set -euo pipefail

REPO=/root/homewroksbothsofthard
OUT="$REPO/project_results/nbody"
FG=/opt/FlameGraph

mkdir -p "$OUT"

require_cmd() {
  local tool="$1"
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "ERROR: Required command not found in PATH: $tool" >&2
    exit 1
  fi
}

require_file() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    echo "ERROR: Required file not found: $path" >&2
    exit 1
  fi
}

files=(
  "$OUT/perf_original_999.data"
  "$OUT/report_original_999.txt"
  "$OUT/out_original_999.perf"
  "$OUT/out_original_999.folded"
  "$OUT/flamegraph_original_999.svg"
  "$OUT/perf_v1_999.data"
  "$OUT/report_v1_999.txt"
  "$OUT/out_v1_999.perf"
  "$OUT/out_v1_999.folded"
  "$OUT/flamegraph_v1_999.svg"
  "$OUT/perf_original_999_dwarf.data"
  "$OUT/report_original_999_dwarf.txt"
  "$OUT/out_original_999_dwarf.perf"
  "$OUT/out_original_999_dwarf.folded"
  "$OUT/flamegraph_original_999_dwarf.svg"
  "$OUT/perf_v1_999_dwarf.data"
  "$OUT/report_v1_999_dwarf.txt"
  "$OUT/out_v1_999_dwarf.perf"
  "$OUT/out_v1_999_dwarf.folded"
  "$OUT/flamegraph_v1_999_dwarf.svg"
)

for f in "${files[@]}"; do
  if [[ -e "$f" ]]; then
    echo "ERROR: Refusing to overwrite existing file: $f" >&2
    echo "Delete or move it first, then rerun this script." >&2
    exit 1
  fi
done

echo "[preflight] Output directory: $OUT"
echo "[preflight] Checking required tooling..."
require_cmd perf
require_cmd python3-dbg
require_file /opt/FlameGraph/stackcollapse-perf.pl
require_file /opt/FlameGraph/flamegraph.pl

echo "[preflight] Required files are absent: safe to proceed."
echo "[preflight] Important: software timing remains authoritative and unchanged."
echo "[preflight] Original: 4.881335 s"
echo "[preflight] V1 scalar: 4.381726 s"
echo "[preflight] Speedup: 1.1140x"
echo "[preflight] Improvement: 10.24%"
echo "[preflight] Profiling is for hotspot analysis only; do not recalculate timing."

run_standard_profile() {
  local label="$1"
  local data_file="$2"
  local report_file="$3"
  local out_perf="$4"
  local out_folded="$5"
  local svg_file="$6"
  local cmd="$7"

  echo
  echo "[profile] $label"
  echo "$cmd"
  eval "$cmd"

  echo "[report] $label"
  perf report --stdio -i "$data_file" > "$report_file"

  echo "[script] $label"
  perf script -i "$data_file" > "$out_perf"

  echo "[folded] $label"
  "$FG/stackcollapse-perf.pl" "$out_perf" > "$out_folded"

  echo "[flamegraph] $label"
  "$FG/flamegraph.pl" "$out_folded" > "$svg_file"
}

run_dwarf_profile() {
  local label="$1"
  local data_file="$2"
  local report_file="$3"
  local out_perf="$4"
  local out_folded="$5"
  local svg_file="$6"
  local cmd="$7"

  echo
  echo "[profile] $label"
  echo "$cmd"
  eval "$cmd"

  echo "[report] $label"
  perf report --stdio -i "$data_file" > "$report_file"

  echo "[script] $label"
  perf script -i "$data_file" > "$out_perf"

  echo "[folded] $label"
  "$FG/stackcollapse-perf.pl" "$out_perf" > "$out_folded"

  echo "[flamegraph] $label"
  "$FG/flamegraph.pl" "$out_folded" > "$svg_file"
}

standard_original_cmd='perf record -F 999 -g -o "$OUT/perf_original_999.data" -- python3-dbg -m pyperformance run --bench nbody'
standard_v1_cmd='perf record -F 999 -g -o "$OUT/perf_v1_999.data" -- python3-dbg /root/homewroksbothsofthard/subNbody/software/run_benchmark_v1_scalar.py'

dwarf_original_cmd='perf record -F 999 --call-graph dwarf -o "$OUT/perf_original_999_dwarf.data" -- python3-dbg -m pyperformance run --bench nbody'
dwarf_v1_cmd='perf record -F 999 --call-graph dwarf -o "$OUT/perf_v1_999_dwarf.data" -- python3-dbg /root/homewroksbothsofthard/subNbody/software/run_benchmark_v1_scalar.py'

run_standard_profile \
  "Original Nbody standard profile (-F 999 -g)" \
  "$OUT/perf_original_999.data" \
  "$OUT/report_original_999.txt" \
  "$OUT/out_original_999.perf" \
  "$OUT/out_original_999.folded" \
  "$OUT/flamegraph_original_999.svg" \
  "$standard_original_cmd"

run_standard_profile \
  "V1 scalar standard profile (-F 999 -g)" \
  "$OUT/perf_v1_999.data" \
  "$OUT/report_v1_999.txt" \
  "$OUT/out_v1_999.perf" \
  "$OUT/out_v1_999.folded" \
  "$OUT/flamegraph_v1_999.svg" \
  "$standard_v1_cmd"

run_dwarf_profile \
  "Original Nbody DWARF profile (--call-graph dwarf)" \
  "$OUT/perf_original_999_dwarf.data" \
  "$OUT/report_original_999_dwarf.txt" \
  "$OUT/out_original_999_dwarf.perf" \
  "$OUT/out_original_999_dwarf.folded" \
  "$OUT/flamegraph_original_999_dwarf.svg" \
  "$dwarf_original_cmd"

run_dwarf_profile \
  "V1 scalar DWARF profile (--call-graph dwarf)" \
  "$OUT/perf_v1_999_dwarf.data" \
  "$OUT/report_v1_999_dwarf.txt" \
  "$OUT/out_v1_999_dwarf.perf" \
  "$OUT/out_v1_999_dwarf.folded" \
  "$OUT/flamegraph_v1_999_dwarf.svg" \
  "$dwarf_v1_cmd"

echo

echo "[compare] Standard original vs standard V1"
echo "  - Compare report_original_999.txt vs report_v1_999.txt"
echo "  - Inspect flamegraph_original_999.svg vs flamegraph_v1_999.svg"
echo "  - Check whether tall-stack artifacts and hotspot conclusions are similar"

echo "[compare] DWARF original vs DWARF V1"
echo "  - Compare report_original_999_dwarf.txt vs report_v1_999_dwarf.txt"
echo "  - Inspect flamegraph_original_999_dwarf.svg vs flamegraph_v1_999_dwarf.svg"

echo "[compare] Standard vs DWARF"
echo "  - Check whether --call-graph dwarf reduces or removes the tall-stack artifact"
echo "  - Check whether the main hotspot conclusions remain consistent"
echo "  - Decide which flamegraph pair is clearer for the final presentation"

echo "[compare] Important: -F 999 -g matches the project PDF format; DWARF is diagnostic and supplementary."
echo "[compare] Timing result remains unchanged: Original=4.881335 s, V1=4.381726 s, Speedup=1.1140x, Improvement=10.24%."
echo

echo "[done] Profile set complete. Files are in: $OUT"
