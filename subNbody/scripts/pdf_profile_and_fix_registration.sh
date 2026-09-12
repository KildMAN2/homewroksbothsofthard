#!/usr/bin/env bash
# End-to-end: fix nbody_v1 pyperformance registration (MANIFEST section-aware),
# verify both benchmarks run, capture PDF-style perf profiles for both,
# generate report/script/folded/flamegraph outputs, and append a short
# summary to subNbody/docs/nbody_project.md.
#
# Hard constraints enforced by this script:
# - Never modifies bm_nbody (original benchmark) source or logic.
# - Never modifies/recreates run_benchmark_v1_scalar.py (V1 source/logic).
# - Never overwrites existing files under project_results/nbody.
# - Never reruns V2/V3/V4, correctness tests, or RTL.
# - Never recomputes or changes the fixed timing numbers.
set -euo pipefail

REPO=/root/homewroksbothsofthard
OUT="$REPO/project_results/nbody"
FG=/opt/FlameGraph
DOC="$REPO/subNbody/docs/nbody_project.md"

BROOT=/opt/pyperformance/pyperformance/data-files/benchmarks
NBODY_DIR="$BROOT/bm_nbody"
V1_DIR="$BROOT/bm_nbody_v1"
MANIFEST="$BROOT/MANIFEST"
V1_SRC="$REPO/subNbody/software/run_benchmark_v1_scalar.py"

mkdir -p "$OUT"

echo "[guard] original nbody registration untouched"
test -f "$NBODY_DIR/pyproject.toml"
test -f "$NBODY_DIR/run_benchmark.py"

echo "[guard] V1 source untouched"
test -f "$V1_SRC"

echo "[guard] bm_nbody_v1/run_benchmark.py already exists (not recreated)"
test -f "$V1_DIR/run_benchmark.py"

# --- Ensure bm_nbody_v1/pyproject.toml exists (only if missing) ---
if [[ -f "$V1_DIR/pyproject.toml" ]]; then
  echo "[skip] $V1_DIR/pyproject.toml already exists"
else
  cat > "$V1_DIR/pyproject.toml" <<'EOF'
[project]
name = "pyperformance_bm_nbody_v1"
requires-python = ">=3.8"
dependencies = ["pyperf"]
urls = {repository = "https://github.com/python/pyperformance"}
dynamic = ["version"]

[tool.pyperformance]
name = "nbody_v1"
tags = "math"
EOF
  echo "[add] created $V1_DIR/pyproject.toml"
fi

# --- Fix MANIFEST: section-aware insertion (previous plain append was wrong) ---
if [[ -f "${MANIFEST}.bak" ]]; then
  echo "[restore] resetting MANIFEST from ${MANIFEST}.bak before reapplying correctly"
  cp -p "${MANIFEST}.bak" "$MANIFEST"
else
  cp -p "$MANIFEST" "${MANIFEST}.bak"
  echo "[backup] saved ${MANIFEST}.bak"
fi

awk '
{
  print
  if ($0 ~ /^nbody[ \t]+<local>[ \t]*$/) {
    line = $0
    sub(/^nbody/, "nbody_v1", line)
    print line
  }
  else if ($0 ~ /^nbody[ \t]*$/) {
    print "nbody_v1"
  }
}
' "$MANIFEST" > "${MANIFEST}.new"
mv "${MANIFEST}.new" "$MANIFEST"

echo "[manifest] entries now present:"
grep -n "nbody" "$MANIFEST"

# --- Verify both benchmarks are runnable ---
echo
echo "[verify] python3-dbg -m pyperformance run --bench nbody"
python3-dbg -m pyperformance run --bench nbody

echo
echo "[verify] python3-dbg -m pyperformance run --bench nbody_v1"
python3-dbg -m pyperformance run --bench nbody_v1

# --- PDF-style official profiling (999 Hz, -g, no DWARF) ---
pdf_files=(
  "$OUT/perf_original_pdf.data"
  "$OUT/report_original_pdf.txt"
  "$OUT/out_original_pdf.perf"
  "$OUT/out_original_pdf.folded"
  "$OUT/flamegraph_original_pdf.svg"
  "$OUT/perf_v1_pdf.data"
  "$OUT/report_v1_pdf.txt"
  "$OUT/out_v1_pdf.perf"
  "$OUT/out_v1_pdf.folded"
  "$OUT/flamegraph_v1_pdf.svg"
)
for f in "${pdf_files[@]}"; do
  if [[ -e "$f" ]]; then
    echo "ERROR: refusing to overwrite existing file: $f" >&2
    exit 1
  fi
done

run_pdf_profile() {
  local label="$1" data="$2" report="$3" perf_out="$4" folded="$5" svg="$6" cmd="$7"
  echo
  echo "[profile] $label"
  echo "$cmd"
  eval "$cmd"
  echo "[report] $label"
  perf report --stdio -i "$data" > "$report"
  echo "[script] $label"
  perf script -i "$data" > "$perf_out"
  echo "[folded] $label"
  "$FG/stackcollapse-perf.pl" "$perf_out" > "$folded"
  echo "[flamegraph] $label"
  "$FG/flamegraph.pl" "$folded" > "$svg"
}

run_pdf_profile \
  "Original nbody (PDF-style, -F 999 -g)" \
  "$OUT/perf_original_pdf.data" "$OUT/report_original_pdf.txt" \
  "$OUT/out_original_pdf.perf" "$OUT/out_original_pdf.folded" \
  "$OUT/flamegraph_original_pdf.svg" \
  'perf record -F 999 -g -o "$OUT/perf_original_pdf.data" -- python3-dbg -m pyperformance run --bench nbody'

run_pdf_profile \
  "V1 scalar nbody_v1 (PDF-style, -F 999 -g)" \
  "$OUT/perf_v1_pdf.data" "$OUT/report_v1_pdf.txt" \
  "$OUT/out_v1_pdf.perf" "$OUT/out_v1_pdf.folded" \
  "$OUT/flamegraph_v1_pdf.svg" \
  'perf record -F 999 -g -o "$OUT/perf_v1_pdf.data" -- python3-dbg -m pyperformance run --bench nbody_v1'

# --- Append a short, factual summary to the existing project doc ---
{
  echo
  echo "## PDF-style profiling run (nbody vs nbody_v1)"
  echo
  echo "- Registered the existing V1 implementation (\`run_benchmark_v1_scalar.py\`, unmodified) as a separate"
  echo "  pyperformance benchmark named \`nbody_v1\` via \`bm_nbody_v1/pyproject.toml\` + a MANIFEST entry."
  echo "  Original \`nbody\` registration and V1 source were not modified."
  echo "- Verified: \`python3-dbg -m pyperformance run --bench nbody\` and \`--bench nbody_v1\` both run."
  echo "- Captured PDF-style profiles: \`perf record -F 999 -g -- python3-dbg -m pyperformance run --bench nbody\`"
  echo "  and the same for \`nbody_v1\`. Outputs saved under \`project_results/nbody/*_pdf.*\` without overwriting"
  echo "  any existing official 999 Hz results."
  echo "- Timing result remains unchanged: Original=4.881335 s, V1=4.381726 s, Speedup=1.1140x, Improvement=10.24%."
} >> "$DOC"

echo
echo "[doc] appended PDF-style profiling summary to $DOC"
echo "[done] Registration fixed, both benchmarks verified, PDF-style profiling complete for nbody and nbody_v1."
