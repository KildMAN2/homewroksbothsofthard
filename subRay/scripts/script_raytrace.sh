#!/usr/bin/env bash
set -euo pipefail

# Main orchestrator for Raytrace benchmark workflow.
# This script wraps existing project scripts and artifacts without changing them.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUBRAY_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$SUBRAY_DIR/.." && pwd)"

MODE="${1:-all}"

print_step() {
  echo
  echo "[script_raytrace] $1"
}

warn() {
  echo "[script_raytrace][warn] $1" >&2
}

die() {
  echo "[script_raytrace][error] $1" >&2
  exit 1
}

usage() {
  cat <<'USAGE'
Usage:
  bash subRay/scripts/script_raytrace.sh baseline
  bash subRay/scripts/script_raytrace.sh optimize
  bash subRay/scripts/script_raytrace.sh profile
  bash subRay/scripts/script_raytrace.sh compare
  bash subRay/scripts/script_raytrace.sh all

Optional environment variables:
  RUNS               Number of perf stat repetitions for profile mode (default: 3)
  PROFILE_TARGET     baseline|attempt1|attempt2|attempt3|final (default: final)
  PROFILE_USE_FAST   0 or 1 (default: 0 for this wrapper)
  PYSPY_NATIVE       0 or 1 for run_profile.sh (default inherited there)
  PYSPY_RATE         py-spy sample rate (default inherited there)
  WIDTH              benchmark width (optimize mode default: 64)
  HEIGHT             benchmark height (optimize mode default: 64)
  OPTIMIZE_USE_FAST  0 or 1 to append --fast in optimize mode (default: 0)
USAGE
}

require_cmd() {
  local cmd="$1"
  local label="$2"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    die "$label is required but not found in PATH: $cmd"
  fi
}

check_common_runtime_deps() {
  require_cmd bash "bash"
  require_cmd python3 "python3"
  require_cmd python3-dbg "python3-dbg"
  require_cmd perf "perf"
}

check_pyperformance_deps() {
  if ! command -v pyperformance >/dev/null 2>&1; then
    warn "pyperformance command not found in PATH"
  fi
  if ! python3 - <<'PY' >/dev/null 2>&1
import importlib.util
raise SystemExit(0 if importlib.util.find_spec('pyperformance') else 1)
PY
  then
    warn "python module 'pyperformance' not found; baseline profiling script may fail"
  fi
}

run_baseline_mode() {
  print_step "Mode: baseline"
  check_common_runtime_deps
  check_pyperformance_deps

  local script="$SCRIPT_DIR/run_baseline.sh"
  [ -x "$script" ] || [ -f "$script" ] || die "Missing script: $script"

  print_step "Running existing baseline workflow: subRay/scripts/run_baseline.sh"
  bash "$script"
}

run_optimize_mode() {
  print_step "Mode: optimize"
  check_common_runtime_deps

  local final_script="$SUBRAY_DIR/optimized/final/run_benchmark.py"
  [ -f "$final_script" ] || die "Missing optimized final benchmark: $final_script"

  local width="${WIDTH:-64}"
  local height="${HEIGHT:-64}"
  local use_fast="${OPTIMIZE_USE_FAST:-0}"

  # Run the existing final optimized benchmark entry directly.
  local cmd=(python3-dbg "$final_script" "--width=$width" "--height=$height")
  if [ "$use_fast" = "1" ]; then
    cmd+=(--fast)
  fi

  print_step "Running final optimized benchmark from subRay/optimized/final/"
  echo "Command: ${cmd[*]}"
  "${cmd[@]}"

  print_step "Note"
  echo "Official locked final result artifact is: $SUBRAY_DIR/results/final_official.txt"
}

run_attempt1_mode() {
  print_step "Mode: attempt1"
  check_common_runtime_deps
  check_pyperformance_deps

  local script="$SCRIPT_DIR/run_attempt1.sh"
  [ -x "$script" ] || [ -f "$script" ] || die "Missing script: $script"

  print_step "Running existing attempt1 workflow: subRay/scripts/run_attempt1.sh"
  bash "$script"
}

run_profile_mode() {
  print_step "Mode: profile"
  check_common_runtime_deps

  local script="$SCRIPT_DIR/run_profile.sh"
  [ -x "$script" ] || [ -f "$script" ] || die "Missing script: $script"

  local target="${PROFILE_TARGET:-final}"
  local runs="${RUNS:-3}"
  local use_fast="${PROFILE_USE_FAST:-0}"

  if ! command -v py-spy >/dev/null 2>&1; then
    warn "py-spy not found. run_profile.sh will still run perf record/report/stat and skip py-spy output."
  fi

  print_step "Running existing profiling workflow: subRay/scripts/run_profile.sh"
  echo "PROFILE_TARGET=$target PROFILE_USE_FAST=$use_fast RUNS=$runs"
  PROFILE_TARGET="$target" PROFILE_USE_FAST="$use_fast" RUNS="$runs" bash "$script"

  # generate_flamegraph.sh expects profiling/perf.data specifically.
  local perf_data="$SUBRAY_DIR/profiling/perf.data"
  local flamegraph_script="$SCRIPT_DIR/generate_flamegraph.sh"
  if [ -f "$perf_data" ] && [ -f "$flamegraph_script" ]; then
    print_step "Found profiling/perf.data; generating flamegraph.svg using existing script"
    bash "$flamegraph_script"
  else
    print_step "Skipping generate_flamegraph.sh"
    echo "Reason: $perf_data was not found (script expects that exact filename)."
    echo "Profiling artifacts from run_profile.sh are preserved under $SUBRAY_DIR/profiling/."
  fi
}

extract_elapsed_line() {
  local file="$1"
  if [ -f "$file" ]; then
    grep -E "seconds time elapsed" "$file" || true
  fi
}

run_compare_mode() {
  print_step "Mode: compare"

  local orig="$SUBRAY_DIR/results/original_official.txt"
  local fin="$SUBRAY_DIR/results/final_official.txt"
  local p1="$SUBRAY_DIR/profiling/perf_stat_attempt1.txt"
  local p2="$SUBRAY_DIR/profiling/perf_stat_attempt2.txt"
  local p3="$SUBRAY_DIR/profiling/perf_stat_attempt3.txt"

  print_step "Official before/after artifacts"
  [ -f "$orig" ] || die "Missing file: $orig"
  [ -f "$fin" ] || die "Missing file: $fin"
  echo "ORIGINAL -> $orig"
  extract_elapsed_line "$orig"
  echo "FINAL    -> $fin"
  extract_elapsed_line "$fin"

  print_step "Profiling attempt perf_stat artifacts (if present)"
  for f in "$p1" "$p2" "$p3"; do
    if [ -f "$f" ]; then
      echo "$(basename "$f")"
      extract_elapsed_line "$f"
    else
      warn "Missing file: $f"
    fi
  done

  print_step "Comparison references"
  echo "$SUBRAY_DIR/reports/final_performance_comparison.txt"
  echo "$SUBRAY_DIR/reports/report_raytrace.txt"
}

print_outputs() {
  print_step "Important output locations"
  echo "Results:   $SUBRAY_DIR/results/"
  echo "Profiling: $SUBRAY_DIR/profiling/"
  echo "Reports:   $SUBRAY_DIR/reports/"
}

run_all_mode() {
  print_step "Mode: all"
  echo "Sequence: baseline -> attempt1 -> optimize(final) -> profile(final, non-fast) -> compare"
  echo "This mode runs the complete software benchmark workflow and preserves existing artifacts."

  run_baseline_mode
  run_attempt1_mode
  run_optimize_mode
  run_profile_mode
  run_compare_mode
}

print_step "Repository root: $REPO_ROOT"
print_step "subRay root: $SUBRAY_DIR"

if [ "$#" -eq 0 ]; then
  print_step "No mode provided; defaulting to 'all'"
  echo "Tip: use '--help' to see all modes."
fi

case "$MODE" in
  baseline)
    run_baseline_mode
    ;;
  optimize)
    run_optimize_mode
    ;;
  profile)
    run_profile_mode
    ;;
  compare)
    run_compare_mode
    ;;
  all)
    run_all_mode
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    usage
    die "Unknown mode: $MODE"
    ;;
esac

print_outputs
