#!/usr/bin/env bash
# Combined perf record / perf report / perf stat / py-spy profiling run for one
# target (baseline / attempt1 / attempt2 / attempt3 / final). Modeled on
# Project/subRay/scripts/run_profile.sh.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE_DIR="$ROOT_DIR/profiling"
LOG_DIR="$ROOT_DIR/logs"

RUNS="${RUNS:-3}"
PYSPY_RATE="${PYSPY_RATE:-100}"
PROFILE_USE_FAST="${PROFILE_USE_FAST:-1}"
PYSPY_NATIVE="${PYSPY_NATIVE:-1}"
PYSPY_SUBPROCESSES="${PYSPY_SUBPROCESSES:-0}"
PERF_EVENTS="${PERF_EVENTS:-cpu-clock,task-clock,cpu-cycles,instructions,cache-references,cache-misses,branches,branch-misses,page-faults,context-switches,cpu-migrations}"
PROFILE_TARGET="${PROFILE_TARGET:-baseline}"

discover_pyflate_script() {
  python3 - <<'PY'
import importlib.util
from pathlib import Path

spec = importlib.util.find_spec("pyperformance")
if not spec or not spec.origin:
  raise SystemExit(1)

base = Path(spec.origin).resolve().parent
candidates = [
  base / "data-files" / "benchmarks" / "bm_pyflate" / "run_benchmark.py",
  Path("/usr/local/lib/python3.10/dist-packages/pyperformance/data-files/benchmarks/bm_pyflate/run_benchmark.py"),
  Path("/usr/lib/python3/dist-packages/pyperformance/data-files/benchmarks/bm_pyflate/run_benchmark.py"),
]

for candidate in candidates:
  if candidate.exists():
    print(candidate)
    raise SystemExit(0)

raise SystemExit(1)
PY
}

PYFLATE_SCRIPT="$(discover_pyflate_script || true)"
ATTEMPT1_SCRIPT="$ROOT_DIR/optimized/attempt1/run_benchmark.py"
ATTEMPT2_SCRIPT="$ROOT_DIR/optimized/attempt2/run_benchmark.py"
ATTEMPT3_SCRIPT="$ROOT_DIR/optimized/attempt3/run_benchmark.py"
FINAL_SCRIPT="$ROOT_DIR/optimized/final/run_benchmark.py"

case "$PROFILE_TARGET" in
  baseline)
    TARGET_NAME="baseline"
    if [ -z "$PYFLATE_SCRIPT" ] || [ ! -f "$PYFLATE_SCRIPT" ]; then
      echo "[run_profile] could not locate pyperformance pyflate script"
      exit 4
    fi
    TARGET_SCRIPT="$PYFLATE_SCRIPT"
    ;;
  attempt1) TARGET_NAME="attempt1"; TARGET_SCRIPT="$ATTEMPT1_SCRIPT" ;;
  attempt2) TARGET_NAME="attempt2"; TARGET_SCRIPT="$ATTEMPT2_SCRIPT" ;;
  attempt3) TARGET_NAME="attempt3"; TARGET_SCRIPT="$ATTEMPT3_SCRIPT" ;;
  final)    TARGET_NAME="final";    TARGET_SCRIPT="$FINAL_SCRIPT" ;;
  *)
    echo "[run_profile] invalid PROFILE_TARGET=$PROFILE_TARGET"
    exit 2
    ;;
esac

PERF_DATA_FILE="$PROFILE_DIR/perf_${TARGET_NAME}.data"
PERF_REPORT_FILE="$PROFILE_DIR/perf_report_${TARGET_NAME}.txt"
PERF_STAT_FILE="$PROFILE_DIR/perf_stat_${TARGET_NAME}.txt"
PYSPY_OUT_FILE="$PROFILE_DIR/flamegraph_pyspy_${TARGET_NAME}.svg"

mkdir -p "$PROFILE_DIR" "$LOG_DIR"
cd "$ROOT_DIR"

CMD=(python3-dbg "$TARGET_SCRIPT")
if [ "$PROFILE_USE_FAST" = "1" ]; then
  CMD+=(--fast)
fi

echo "[run_profile] target=$TARGET_NAME script=$TARGET_SCRIPT fast=$PROFILE_USE_FAST"

echo "[run_profile] perf record -> $PERF_DATA_FILE"
set +e
/usr/bin/perf record -F 999 -g -o "$PERF_DATA_FILE" -- "${CMD[@]}" > /dev/null 2>&1
PERF_STATUS=$?
set -e

echo "[run_profile] perf report -> $PERF_REPORT_FILE"
set +e
/usr/bin/perf report --stdio -i "$PERF_DATA_FILE" > "$PERF_REPORT_FILE" 2>/dev/null
PERF_REPORT_STATUS=$?
set -e

echo "[run_profile] perf stat -> $PERF_STAT_FILE"
set +e
/usr/bin/perf stat -r "$RUNS" \
  -e "$PERF_EVENTS" \
  -- "${CMD[@]}" \
  > /dev/null 2> "$PERF_STAT_FILE"
PERF_STAT_STATUS=$?
set -e

if ! command -v py-spy >/dev/null 2>&1; then
  echo "[run_profile] py-spy is not installed; skipped $PYSPY_OUT_FILE"
  echo "[run_profile] statuses: perf=$PERF_STATUS perf_report=$PERF_REPORT_STATUS perf_stat=$PERF_STAT_STATUS pyspy=missing"
  exit 0
fi

PYSPY_CMD=(py-spy record --rate "$PYSPY_RATE")
if [ "$PYSPY_NATIVE" = "1" ]; then
  PYSPY_CMD+=(--native)
fi
if [ "$PYSPY_SUBPROCESSES" = "1" ]; then
  PYSPY_CMD+=(--subprocesses)
fi
PYSPY_CMD+=(--output "$PYSPY_OUT_FILE" -- "${CMD[@]}")

echo "[run_profile] py-spy -> $PYSPY_OUT_FILE"
set +e
"${PYSPY_CMD[@]}"
PYSPY_STATUS=$?
set -e

echo "[run_profile] statuses: perf=$PERF_STATUS perf_report=$PERF_REPORT_STATUS perf_stat=$PERF_STAT_STATUS pyspy=$PYSPY_STATUS"
