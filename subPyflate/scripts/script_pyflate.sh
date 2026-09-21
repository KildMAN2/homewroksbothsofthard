#!/usr/bin/env bash
# Main orchestrator for the pyflate benchmark workflow (mirrors
# subRay/scripts/script_raytrace.sh with pyflate-specific commands).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUBPYFLATE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$SUBPYFLATE_DIR/.." && pwd)"

export PATH="$HOME/.local/bin:/usr/local/bin:$PATH"

MODE="${1:-all}"

print_step() { echo; echo "[script_pyflate] $1"; }
warn()       { echo "[script_pyflate][warn] $1" >&2; }
die()        { echo "[script_pyflate][error] $1" >&2; exit 1; }

usage() {
  cat <<'USAGE'
Usage:
  bash subPyflate/scripts/script_pyflate.sh baseline
  bash subPyflate/scripts/script_pyflate.sh optimize
  bash subPyflate/scripts/script_pyflate.sh attempt1
  bash subPyflate/scripts/script_pyflate.sh profile
  bash subPyflate/scripts/script_pyflate.sh profile-suite
  bash subPyflate/scripts/script_pyflate.sh compare
  bash subPyflate/scripts/script_pyflate.sh check
  bash subPyflate/scripts/script_pyflate.sh all

Environment variables (subset):
  RUNS               perf stat repetitions (default: 3)
  PROFILE_TARGET     baseline|attempt1|attempt2|attempt3|final (default: final)
  PROFILE_USE_FAST   0 or 1 (default for `profile` mode: 0)
  OPTIMIZE_USE_FAST  0 or 1 (append --fast when calling the final directly)
USAGE
}

require_cmd() {
  local cmd="$1"; local label="$2"
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
  [ -f "$script" ] || die "Missing script: $script"
  bash "$script"
}

run_attempt1_mode() {
  print_step "Mode: attempt1"
  check_common_runtime_deps
  check_pyperformance_deps
  local script="$SCRIPT_DIR/run_attempt1.sh"
  [ -f "$script" ] || die "Missing script: $script"
  bash "$script"
}

run_optimize_mode() {
  print_step "Mode: optimize"
  check_common_runtime_deps

  local final_script="$SUBPYFLATE_DIR/optimized/final/run_benchmark.py"
  [ -f "$final_script" ] || die "Missing optimized final benchmark: $final_script"

  local use_fast="${OPTIMIZE_USE_FAST:-0}"
  local cmd=(python3-dbg "$final_script")
  if [ "$use_fast" = "1" ]; then
    cmd+=(--fast)
  fi

  print_step "Running final optimized benchmark from subPyflate/optimized/final/"
  echo "Command: ${cmd[*]}"
  "${cmd[@]}"
}

run_profile_mode() {
  print_step "Mode: profile"
  check_common_runtime_deps
  local script="$SCRIPT_DIR/run_profile.sh"
  [ -f "$script" ] || die "Missing script: $script"

  local target="${PROFILE_TARGET:-final}"
  local runs="${RUNS:-3}"
  local use_fast="${PROFILE_USE_FAST:-0}"

  if ! command -v py-spy >/dev/null 2>&1; then
    warn "py-spy not found. run_profile.sh will still run perf record/report/stat and skip py-spy."
  fi

  PROFILE_TARGET="$target" PROFILE_USE_FAST="$use_fast" RUNS="$runs" bash "$script"

  local target_perf_data="$SUBPYFLATE_DIR/profiling/perf_${target}.data"
  local perf_data="$SUBPYFLATE_DIR/profiling/perf.data"
  local flamegraph_script="$SCRIPT_DIR/generate_flamegraph.sh"
  if [ -f "$target_perf_data" ] && [ -f "$flamegraph_script" ]; then
    print_step "Generating perf flamegraph.svg from perf_${target}.data"
    cp -f "$target_perf_data" "$perf_data"
    bash "$flamegraph_script"
    if [ -f "$SUBPYFLATE_DIR/profiling/flamegraph.svg" ]; then
      cp -f "$SUBPYFLATE_DIR/profiling/flamegraph.svg" \
            "$SUBPYFLATE_DIR/profiling/flamegraph_${target}.svg"
    fi
  fi
}

run_profile_suite_mode() {
  print_step "Mode: profile-suite"
  check_common_runtime_deps
  check_pyperformance_deps
  require_cmd perf "perf"

  local target="${PROFILE_TARGET:-baseline}"
  local produced_perf_data=""

  case "$target" in
    baseline)
      local bscript="$SCRIPT_DIR/run_baseline.sh"
      [ -f "$bscript" ] || die "Missing script: $bscript"
      bash "$bscript"
      produced_perf_data="$SUBPYFLATE_DIR/results/baseline/perf.data"
      ;;
    attempt1)
      local ascript="$SCRIPT_DIR/run_attempt1.sh"
      [ -f "$ascript" ] || die "Missing script: $ascript"
      bash "$ascript"
      produced_perf_data="$SUBPYFLATE_DIR/results/attempt1/perf.data"
      ;;
    attempt2|attempt3|final)
      local manifest="" bench=""
      case "$target" in
        attempt2) manifest="$SUBPYFLATE_DIR/optimized/attempt2/MANIFEST"; bench="pyflate_attempt2" ;;
        attempt3) manifest="$SUBPYFLATE_DIR/optimized/attempt3/MANIFEST"; bench="pyflate_attempt3" ;;
        final)    manifest="$SUBPYFLATE_DIR/optimized/final/MANIFEST";    bench="pyflate_final" ;;
      esac
      [ -f "$manifest" ] || die "Missing manifest: $manifest"
      produced_perf_data="$SUBPYFLATE_DIR/results/${target}/perf.data"
      mkdir -p "$SUBPYFLATE_DIR/results/${target}"
      cd "$SUBPYFLATE_DIR"
      perf record -F 999 -g -o "$produced_perf_data" -- \
        python3-dbg -m pyperformance run --manifest "$manifest" --bench "$bench"
      ;;
    *) die "invalid PROFILE_TARGET=$target" ;;
  esac

  local report_file="$SUBPYFLATE_DIR/profiling/perf_report_suite_${target}.txt"
  [ -f "$produced_perf_data" ] || { warn "no perf data $produced_perf_data"; return 0; }

  perf report --stdio -i "$produced_perf_data" > "$report_file" 2>/dev/null

  local perf_data="$SUBPYFLATE_DIR/profiling/perf.data"
  local flamegraph_script="$SCRIPT_DIR/generate_flamegraph.sh"
  if [ -f "$flamegraph_script" ]; then
    cp -f "$produced_perf_data" "$perf_data"
    bash "$flamegraph_script"
    if [ -f "$SUBPYFLATE_DIR/profiling/flamegraph.svg" ]; then
      cp -f "$SUBPYFLATE_DIR/profiling/flamegraph.svg" \
            "$SUBPYFLATE_DIR/profiling/flamegraph_suite_${target}.svg"
    fi
  fi
}

extract_elapsed_line() {
  local file="$1"
  [ -f "$file" ] && grep -E "seconds time elapsed" "$file" || true
}

extract_mean_seconds() {
  local file="$1"
  awk '/seconds time elapsed/ { print $1; exit }' "$file"
}

show_report_hotspots() {
  local label="$1"; local file="$2"
  if [ -f "$file" ]; then
    echo "$label -> $file"
    awk '/^[[:space:]]+[0-9.]+%[[:space:]]+[0-9.]+%/ && $NF != "" {
      printf "  %s %s\n", $1, $NF
      count++
      if (count == 5) exit
    }' "$file"
  else
    warn "Missing perf report: $file"
  fi
}

run_compare_mode() {
  print_step "Mode: compare"

  local orig="$SUBPYFLATE_DIR/results/original_official.txt"
  local fin="$SUBPYFLATE_DIR/results/final_official.txt"
  local pf="$SUBPYFLATE_DIR/profiling/perf_stat_final.txt"
  local rb="$SUBPYFLATE_DIR/profiling/perf_report_baseline.txt"
  local rf="$SUBPYFLATE_DIR/profiling/perf_report_final.txt"

  print_step "Official before/after artifacts"
  [ -f "$orig" ] || die "Missing file: $orig"
  [ -f "$fin" ]  || die "Missing file: $fin"
  echo "ORIGINAL -> $orig"; extract_elapsed_line "$orig"
  echo "FINAL    -> $fin"; extract_elapsed_line "$fin"

  local original_seconds final_seconds
  original_seconds="$(extract_mean_seconds "$orig")"
  final_seconds="$(extract_mean_seconds "$fin")"
  if [ -n "$original_seconds" ] && [ -n "$final_seconds" ]; then
    print_step "Original vs final comparison"
    awk -v original="$original_seconds" -v final="$final_seconds" 'BEGIN {
      printf "Original mean: %.6f s\n", original
      printf "Final mean:    %.6f s\n", final
      printf "Speedup:       %.2fx\n", original / final
      printf "Improvement:   %.2f%%\n", (original - final) / original * 100
    }'
  fi

  print_step "Perf report baseline vs final hotspots"
  show_report_hotspots "BASELINE" "$rb"
  show_report_hotspots "FINAL"    "$rf"

  local generated="$SUBPYFLATE_DIR/reports/compare_generated.txt"
  {
    echo "Pyflate generated comparison"
    echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo
    echo "Official original: $(extract_elapsed_line "$orig")"
    echo "Official final:    $(extract_elapsed_line "$fin")"
    if [ -n "$original_seconds" ] && [ -n "$final_seconds" ]; then
      awk -v original="$original_seconds" -v final="$final_seconds" 'BEGIN {
        printf "Speedup:     %.2fx\n", original / final
        printf "Improvement: %.2f%%\n", (original - final) / original * 100
      }'
    fi
    echo
    echo "Final perf_stat: $(extract_elapsed_line "$pf")"
    echo "Baseline perf report: $rb"
    echo "Final perf report:    $rf"
  } > "$generated"
  echo "$generated"
}

run_check_mode() {
  print_step "Mode: check (correctness for attempt1/2/3/final)"
  require_cmd python3 "python3"
  local failures=0
  for target in attempt1 attempt2 attempt3 final; do
    print_step "Correctness: $target"
    if ! python3 "$SCRIPT_DIR/check_attempt_correctness.py" "$target"; then
      warn "correctness FAILED for $target"
      failures=$((failures + 1))
    fi
  done
  if [ "$failures" -ne 0 ]; then
    die "$failures correctness check(s) failed"
  fi
}

run_all_mode() {
  print_step "Mode: all"
  echo "Sequence: baseline -> attempt1 -> optimize(final) -> profile(final) -> check -> compare"
  run_baseline_mode
  run_attempt1_mode
  run_optimize_mode
  run_profile_mode
  run_check_mode
  run_compare_mode
}

print_step "Repository root: $REPO_ROOT"
print_step "subPyflate root: $SUBPYFLATE_DIR"

case "$MODE" in
  baseline)      run_baseline_mode ;;
  attempt1)      run_attempt1_mode ;;
  optimize)      run_optimize_mode ;;
  profile)       run_profile_mode ;;
  profile-suite) run_profile_suite_mode ;;
  compare)       run_compare_mode ;;
  check)         run_check_mode ;;
  all)           run_all_mode ;;
  help|-h|--help) usage ;;
  *) usage; die "Unknown mode: $MODE" ;;
esac
