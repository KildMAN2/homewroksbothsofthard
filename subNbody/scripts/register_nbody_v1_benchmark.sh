#!/usr/bin/env bash
# Registers the EXISTING V1 implementation as a separate pyperformance
# benchmark named "nbody_v1", mirroring exactly how the original "nbody"
# benchmark is registered (pyproject.toml + MANIFEST entry).
#
# Safety / scope:
# - Does NOT modify bm_nbody (original benchmark) in any way.
# - Does NOT modify or recreate run_benchmark_v1_scalar.py (V1 source).
# - Only ADDS missing files/lines for bm_nbody_v1. Idempotent: safe to rerun.
# - Backs up MANIFEST before the first modification.
set -euo pipefail

BROOT=/opt/pyperformance/pyperformance/data-files/benchmarks
NBODY_DIR="$BROOT/bm_nbody"
V1_DIR="$BROOT/bm_nbody_v1"
MANIFEST="$BROOT/MANIFEST"
V1_SRC=/root/homewroksbothsofthard/subNbody/software/run_benchmark_v1_scalar.py

echo "[check] original nbody registration must exist and stays untouched"
test -f "$NBODY_DIR/pyproject.toml"
test -f "$NBODY_DIR/run_benchmark.py"

echo "[check] existing V1 source must exist and stays untouched"
test -f "$V1_SRC"

echo "[check] bm_nbody_v1/run_benchmark.py must already exist"
test -f "$V1_DIR/run_benchmark.py"

# --- 1. Add bm_nbody_v1/pyproject.toml (only if missing) ---
if [[ -f "$V1_DIR/pyproject.toml" ]]; then
  echo "[skip] $V1_DIR/pyproject.toml already exists, leaving as-is"
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

# --- 2. Add MANIFEST entry for nbody_v1 (only if missing) ---
if grep -qE '^nbody_v1[[:space:]]' "$MANIFEST"; then
  echo "[skip] MANIFEST already has an nbody_v1 entry"
else
  if [[ ! -f "${MANIFEST}.bak" ]]; then
    cp -p "$MANIFEST" "${MANIFEST}.bak"
    echo "[backup] saved ${MANIFEST}.bak"
  fi

  nbody_line="$(grep -E '^nbody[[:space:]]' "$MANIFEST" | head -1)"
  if [[ -z "$nbody_line" ]]; then
    echo "ERROR: could not find existing 'nbody' line in MANIFEST to mirror format" >&2
    exit 1
  fi

  # Reuse the exact same trailing whitespace/format as the 'nbody' line.
  suffix="${nbody_line#nbody}"
  new_line="nbody_v1${suffix}"
  printf '%s\n' "$new_line" >> "$MANIFEST"
  echo "[add] appended to MANIFEST: $new_line"
fi

echo
echo "[verify] python3-dbg -m pyperformance run --bench nbody_v1"
python3-dbg -m pyperformance run --bench nbody_v1

echo
echo "[done] nbody_v1 registered. Original nbody and V1 source were not modified."
