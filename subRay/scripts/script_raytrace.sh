#!/usr/bin/env bash
set -euo pipefail

# Main orchestrator for Raytrace benchmark workflow.
# This script wraps existing project scripts and artifacts without changing them.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUBRAY_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$SUBRAY_DIR/.." && pwd)"

# Ensure user-local install dirs are searched so tools like py-spy are found.
export PATH="$HOME/.local/bin:/usr/local/bin:$PATH"

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
  bash subRay/scripts/script_raytrace.sh profile-suite
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

  # run_profile.sh writes a target-specific perf_<target>.data, but
  # generate_flamegraph.sh reads exactly profiling/perf.data; bridge them here.
  local target_perf_data="$SUBRAY_DIR/profiling/perf_${target}.data"
  local perf_data="$SUBRAY_DIR/profiling/perf.data"
  local flamegraph_script="$SCRIPT_DIR/generate_flamegraph.sh"
  if [ -f "$target_perf_data" ] && [ -f "$flamegraph_script" ]; then
    print_step "Generating perf flamegraph.svg from perf_${target}.data"
    cp -f "$target_perf_data" "$perf_data"
    bash "$flamegraph_script"
    local target_flamegraph="$SUBRAY_DIR/profiling/flamegraph_${target}.svg"
    if [ -f "$SUBRAY_DIR/profiling/flamegraph.svg" ]; then
      cp -f "$SUBRAY_DIR/profiling/flamegraph.svg" "$target_flamegraph"
      echo "Perf flamegraph: $target_flamegraph"
    fi
  else
    print_step "Skipping generate_flamegraph.sh"
    echo "Reason: $target_perf_data was not found."
    echo "Profiling artifacts from run_profile.sh are preserved under $SUBRAY_DIR/profiling/."
  fi
}

extract_elapsed_line() {
  local file="$1"
  if [ -f "$file" ]; then
    grep -E "seconds time elapsed" "$file" || true
  fi
}

extract_mean_seconds() {
  local file="$1"
  awk '/seconds time elapsed/ { print $1; exit }' "$file"
}

# Full pyperformance-methodology profiling. Reuses run_baseline.sh / run_attempt1.sh
# for those targets so it exactly matches the existing baseline/attempt1 scripts.
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
      print_step "Reusing existing baseline script: run_baseline.sh"
      bash "$bscript"
      produced_perf_data="$SUBRAY_DIR/results/baseline/perf.data"
      ;;
    attempt1)
      local ascript="$SCRIPT_DIR/run_attempt1.sh"
      [ -f "$ascript" ] || die "Missing script: $ascript"
      print_step "Reusing existing attempt1 script: run_attempt1.sh"
      bash "$ascript"
      produced_perf_data="$SUBRAY_DIR/results/attempt1/perf.data"
      ;;
    attempt2|attempt3|final)
      # No dedicated script exists for these; replicate the same pyperformance command.
      local manifest="" bench=""
      case "$target" in
        attempt2) manifest="$SUBRAY_DIR/optimized/attempt2/MANIFEST"; bench="raytrace_attempt2" ;;
        attempt3) manifest="$SUBRAY_DIR/optimized/attempt3/MANIFEST"; bench="raytrace_attempt3" ;;
        final)    manifest="$SUBRAY_DIR/optimized/final/MANIFEST"; bench="raytrace_final" ;;
      esac
      [ -f "$manifest" ] || die "Missing manifest: $manifest"
      produced_perf_data="$SUBRAY_DIR/results/${target}/perf.data"
      mkdir -p "$SUBRAY_DIR/results/${target}"
      cd "$SUBRAY_DIR"
      print_step "perf record (full pyperformance run) -> $produced_perf_data"
      echo "perf record -F 999 -g -o $produced_perf_data -- python3-dbg -m pyperformance run --manifest $manifest --bench $bench"
      perf record -F 999 -g -o "$produced_perf_data" -- python3-dbg -m pyperformance run --manifest "$manifest" --bench "$bench"
      ;;
    *) die "invalid PROFILE_TARGET=$target (use baseline, attempt1, attempt2, attempt3, or final)" ;;
  esac

  local report_file="$SUBRAY_DIR/profiling/perf_report_suite_${target}.txt"
  if [ ! -f "$produced_perf_data" ]; then
    warn "Expected perf data not found: $produced_perf_data"
    return 0
  fi

  print_step "perf report --stdio -> $report_file"
  perf report --stdio -i "$produced_perf_data" > "$report_file" 2>/dev/null
  echo "Suite perf report: $report_file"

  # Perf flamegraph via existing generator, which reads exactly profiling/perf.data.
  local perf_data="$SUBRAY_DIR/profiling/perf.data"
  local flamegraph_script="$SCRIPT_DIR/generate_flamegraph.sh"
  if [ -f "$flamegraph_script" ]; then
    print_step "Generating suite flamegraph.svg from $target perf data"
    cp -f "$produced_perf_data" "$perf_data"
    bash "$flamegraph_script"
    local suite_flamegraph="$SUBRAY_DIR/profiling/flamegraph_suite_${target}.svg"
    if [ -f "$SUBRAY_DIR/profiling/flamegraph.svg" ]; then
      cp -f "$SUBRAY_DIR/profiling/flamegraph.svg" "$suite_flamegraph"
      echo "Suite flamegraph: $suite_flamegraph"
    fi
  else
    warn "generate_flamegraph.sh not found; skipped suite flamegraph."
  fi
}


show_report_hotspots() {
  local label="$1"
  local file="$2"
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

  local orig="$SUBRAY_DIR/results/original_official.txt"
  local fin="$SUBRAY_DIR/results/final_official.txt"
  local p1="$SUBRAY_DIR/profiling/perf_stat_attempt1.txt"
  local p2="$SUBRAY_DIR/profiling/perf_stat_attempt2.txt"
  local p3="$SUBRAY_DIR/profiling/perf_stat_attempt3.txt"
  local pf="$SUBRAY_DIR/profiling/perf_stat_final.txt"
  local rb="$SUBRAY_DIR/profiling/perf_report_suite_baseline.txt"
  local rf="$SUBRAY_DIR/profiling/perf_report_suite_final.txt"
  local rb_single="$SUBRAY_DIR/profiling/perf_report_baseline.txt"
  local rf_single="$SUBRAY_DIR/profiling/perf_report_final.txt"

  print_step "Official before/after artifacts"
  [ -f "$orig" ] || die "Missing file: $orig"
  [ -f "$fin" ] || die "Missing file: $fin"
  echo "ORIGINAL -> $orig"
  extract_elapsed_line "$orig"
  echo "FINAL    -> $fin"
  extract_elapsed_line "$fin"

  local original_seconds
  local final_seconds
  original_seconds="$(extract_mean_seconds "$orig")"
  final_seconds="$(extract_mean_seconds "$fin")"
  if [ -n "$original_seconds" ] && [ -n "$final_seconds" ]; then
    print_step "Original vs final comparison"
    awk -v original="$original_seconds" -v final="$final_seconds" 'BEGIN {
      speedup = original / final
      improvement = (original - final) / original * 100
      printf "Original mean: %.6f s\n", original
      printf "Final mean:    %.6f s\n", final
      printf "Speedup:       %.2fx\n", speedup
      printf "Improvement:   %.2f%%\n", improvement
    }'
  else
    warn "Could not extract elapsed times from official result files; showing artifacts only."
  fi

  print_step "Profiling attempt perf_stat artifacts (if present)"
  for f in "$p1" "$p2" "$p3"; do
    if [ -f "$f" ]; then
      echo "$(basename "$f")"
      extract_elapsed_line "$f"
    else
      warn "Missing file: $f"
    fi
  done

  print_step "Final profiling artifacts"
  if [ -f "$pf" ]; then
    echo "perf_stat_final.txt"
    extract_elapsed_line "$pf"
  else
    warn "Missing file: $pf"
  fi
  if [ -f "$rf" ]; then
    echo "perf_report_suite_final.txt -> $rf"
  else
    warn "Missing file: $rf"
  fi

  print_step "Perf report hotspots (authoritative suite pair)"
  show_report_hotspots "SUITE BASELINE" "$rb"
  show_report_hotspots "SUITE FINAL" "$rf"

  print_step "Perf report hotspots (single-run pair, supplemental)"
  show_report_hotspots "BASELINE" "$rb_single"
  show_report_hotspots "FINAL" "$rf_single"
  echo "Note: perf percentages are relative shares of each run, not absolute time; speedup is proven by wall-clock time above."

  # Write a fresh generated comparison file; the curated file is never overwritten.
  local generated="$SUBRAY_DIR/reports/compare_generated.txt"
  {
    echo "Raytrace generated comparison"
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
    echo "Suite baseline perf report: $rb"
    echo "Suite final perf report:    $rf"
    echo "Single-run baseline perf report: $rb_single"
    echo "Single-run final perf report:    $rf_single"
  } > "$generated"
  print_step "Generated comparison file written"
  echo "$generated"

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
  profile-suite)
    run_profile_suite_mode
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
