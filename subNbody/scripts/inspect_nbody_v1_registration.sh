#!/usr/bin/env bash
# Read-only inspection script.
# Does NOT create, modify, or delete anything.
# Purpose: gather the exact facts needed to register the existing V1
# implementation as a separate pyperformance benchmark named nbody_v1,
# without touching the original nbody benchmark or the V1 source file.

BROOT=/opt/pyperformance/pyperformance/data-files/benchmarks

echo "=== [1] Original bm_nbody directory listing ==="
ls -la "$BROOT/bm_nbody/" 2>&1

echo
echo "=== [2] Original bm_nbody/pyproject.toml (if present) ==="
cat "$BROOT/bm_nbody/pyproject.toml" 2>&1

echo
echo "=== [3] Leftover bm_nbody_v1 directory listing (if present) ==="
ls -la "$BROOT/bm_nbody_v1/" 2>&1

echo
echo "=== [4] Leftover bm_nbody_v1/run_benchmark.py contents (if present) ==="
cat "$BROOT/bm_nbody_v1/run_benchmark.py" 2>&1

echo
echo "=== [5] Leftover bm_nbody_v1/pyproject.toml (if present) ==="
cat "$BROOT/bm_nbody_v1/pyproject.toml" 2>&1

echo
echo "=== [6] Any MANIFEST file under the pyperformance data-files tree ==="
find /opt/pyperformance -maxdepth 4 -iname "MANIFEST*" 2>&1

echo
echo "=== [7] nbody references inside any MANIFEST found ==="
find /opt/pyperformance -maxdepth 4 -iname "MANIFEST*" -exec grep -n -i "nbody" {} + 2>&1

echo
echo "=== [8] Any other .toml files across pyperformance mentioning nbody ==="
find /opt/pyperformance -iname "*.toml" 2>/dev/null | xargs grep -l -i "nbody" 2>/dev/null

echo
echo "=== [9] Confirm existing V1 source file is untouched ==="
ls -l /root/homewroksbothsofthard/subNbody/software/run_benchmark_v1_scalar.py 2>&1

echo
echo "=== [10] pyperformance version / install location ==="
python3-dbg -c "import pyperformance, os; print(pyperformance.__file__)" 2>&1

echo
echo "=== Inspection complete. No files were created or modified. ==="
