#!/usr/bin/env bash
set -euo pipefail

REPO=/root/homewroksbothsofthard
OUT="$REPO/project_results/nbody"
FG=/opt/FlameGraph
PYPERF_BENCH_ROOT="${PYPERF_BENCH_ROOT:-/opt/pyperformance/pyperformance/data-files/benchmarks}"
V1_BENCH_DIR="$PYPERF_BENCH_ROOT/bm_nbody_v1"
V1_BENCH_FILE="$V1_BENCH_DIR/run_benchmark.py"
V1_SRC="$REPO/subNbody/software/run_benchmark_v1_scalar.py"

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

check_no_overwrite() {
  local files=("$@")
  for f in "${files[@]}"; do
    if [[ -e "$f" ]]; then
      echo "ERROR: Refusing to overwrite existing file: $f" >&2
      echo "Delete or move it first, then rerun this script." >&2
      exit 1
    fi
  done
}

ensure_nbody_v1_registration() {
  if [[ ! -f "$V1_SRC" ]]; then
    echo "ERROR: V1 source not found: $V1_SRC" >&2
    exit 1
  fi

  if [[ -f "$V1_BENCH_FILE" ]]; then
    echo "[pyperformance] Reusing existing V1 registration at $V1_BENCH_FILE"
    return 0
  fi

  mkdir -p "$V1_BENCH_DIR"
  cat > "$V1_BENCH_FILE" <<'PY'
#!/usr/bin/env python3
import importlib.util
from pathlib import Path

import pyperf

V1_SRC = Path("/root/homewroksbothsofthard/subNbody/software/run_benchmark_v1_scalar.py")
spec = importlib.util.spec_from_file_location("nbody_v1_impl", V1_SRC)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

DEFAULT_ITERATIONS = getattr(mod, "DEFAULT_ITERATIONS", 20000)
DEFAULT_REFERENCE = getattr(mod, "DEFAULT_REFERENCE", "sun")


def add_cmdline_args(cmd, args):
    cmd.extend(("--iterations", str(args.iterations)))


if __name__ == "__main__":
    runner = pyperf.Runner(add_cmdline_args=add_cmdline_args)
    runner.metadata["description"] = "n-body benchmark V1 scalar"
    runner.argparser.add_argument("--iterations",
                                  type=int,
                                  default=DEFAULT_ITERATIONS,
                                  help="Number of nbody advance() iterations "
                                       "(default: %s)" % DEFAULT_ITERATIONS)
    runner.argparser.add_argument("--reference",
                                  type=str,
                                  default=DEFAULT_REFERENCE,
                                  help="nbody reference (default: %s)"
                                       % DEFAULT_REFERENCE)
    args = runner.parse_args()
    runner.bench_time_func("nbody_v1", mod.bench_nbody,
                           args.reference, args.iterations)
PY
  chmod +x "$V1_BENCH_FILE"
  echo "[pyperformance] Registered nbody_v1 at $V1_BENCH_FILE"
}

official_files=(
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
)

echo "[preflight] Output directory: $OUT"
echo "[preflight] Checking required tooling..."
require_cmd perf
require_cmd python3-dbg
require_file /opt/FlameGraph/stackcollapse-perf.pl
require_file /opt/FlameGraph/flamegraph.pl

echo "[preflight] Official project profiling remains 999 Hz with -g only."
echo "[preflight] DWARF at 999 Hz is explicitly not retried because it exhausted VM memory and generated ~3.2 GB files."
echo "[preflight] Important: software timing remains authoritative and unchanged."
echo "[preflight] Original: 4.881335 s"
echo "[preflight] V1 scalar: 4.381726 s"
echo "[preflight] Speedup: 1.1140x"
echo "[preflight] Improvement: 10.24%"
echo "[preflight] Profiling is for hotspot analysis only; do not recalculate timing."

echo "[pyperformance] Ensuring a separate V1 benchmark named nbody_v1 is registered without altering the original nbody benchmark."
ensure_nbody_v1_registration

check_no_overwrite "${official_files[@]}"

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

standard_original_cmd='perf record -F 999 -g -o "$OUT/perf_original_999.data" -- python3-dbg -m pyperformance run --bench nbody'
standard_v1_cmd='perf record -F 999 -g -o "$OUT/perf_v1_999.data" -- python3-dbg -m pyperformance run --bench nbody_v1'

run_standard_profile \
  "Original Nbody official profile (-F 999 -g)" \
  "$OUT/perf_original_999.data" \
  "$OUT/report_original_999.txt" \
  "$OUT/out_original_999.perf" \
  "$OUT/out_original_999.folded" \
  "$OUT/flamegraph_original_999.svg" \
  "$standard_original_cmd"

run_standard_profile \
  "V1 scalar official profile (-F 999 -g)" \
  "$OUT/perf_v1_999.data" \
  "$OUT/report_v1_999.txt" \
  "$OUT/out_v1_999.perf" \
  "$OUT/out_v1_999.folded" \
  "$OUT/flamegraph_v1_999.svg" \
  "$standard_v1_cmd"

echo

echo "[verify] Run this to confirm the V1 registration works: python3-dbg -m pyperformance run --bench nbody_v1"
echo "[compare] Timing result remains unchanged: Original=4.881335 s, V1=4.381726 s, Speedup=1.1140x, Improvement=10.24%."
echo "[done] Official 999 -g profiling complete for original nbody and registered nbody_v1."
