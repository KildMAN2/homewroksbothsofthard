#!/bin/bash
# HW2 — Hotel Management System
# Build, Run, and Performance Profiling Script
# Usage: bash script.sh

set -e

TRAD_DIR="Traditional"
FAAS_DIR="FaaS"
TRAD_BIN="$TRAD_DIR/hotel_traditional"
FAAS_BIN="$FAAS_DIR/hotel_faas"
TRAD_EXT_BIN="$TRAD_DIR/hotel_traditional_ext"
FAAS_EXT_BIN="$FAAS_DIR/hotel_faas_ext"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  HW2: Hotel Management System${NC}"
echo -e "${CYAN}========================================${NC}\n"

# ── 0. Cleanup + disk space guard ──────────────────────────────────────────────
# Rebuilding repeatedly can leave stale binaries/objects around, and a full
# /tmp is a common cause of "No space left on device" during compilation on
# shared VMs. Clean previous build artifacts and point the compiler's temp
# files at a local, project-owned directory instead of the (possibly full)
# system /tmp.
echo -e "${YELLOW}[0/4] Cleaning previous build artifacts...${NC}"
rm -f "$TRAD_DIR"/*.o "$FAAS_DIR"/*.o
rm -f "$TRAD_BIN" "$TRAD_EXT_BIN" "$FAAS_BIN" "$FAAS_EXT_BIN"

BUILD_TMPDIR="$(pwd)/.build_tmp"
mkdir -p "$BUILD_TMPDIR"
export TMPDIR="$BUILD_TMPDIR"
trap 'rm -rf "$BUILD_TMPDIR"' EXIT

echo "Disk usage for current filesystem:"
df -h . | awk 'NR==1 || NR==2'
echo ""

# ── 1. Build ──────────────────────────────────────────────────────────────────

echo -e "${YELLOW}[1/4] Building Traditional architecture...${NC}"
g++ -O2 -std=c++17 -g -Wall \
    -o "$TRAD_BIN" \
    "$TRAD_DIR/hotel_system.cpp" "$TRAD_DIR/main.cpp"
g++ -O2 -std=c++17 -g -Wall \
    -o "$TRAD_EXT_BIN" \
    "$TRAD_DIR/hotel_system.cpp" "$TRAD_DIR/feature_extension.cpp"
echo -e "${GREEN}      Built: $TRAD_BIN and $TRAD_EXT_BIN${NC}"

echo -e "${YELLOW}[2/4] Building FaaS architecture...${NC}"
g++ -O2 -std=c++17 -g -Wall \
    -o "$FAAS_BIN" \
    "$FAAS_DIR/storage.cpp" "$FAAS_DIR/faas_functions.cpp" "$FAAS_DIR/main.cpp"
g++ -O2 -std=c++17 -g -Wall \
    -o "$FAAS_EXT_BIN" \
    "$FAAS_DIR/storage.cpp" "$FAAS_DIR/faas_functions.cpp" "$FAAS_DIR/feature_extension.cpp"
echo -e "${GREEN}      Built: $FAAS_BIN and $FAAS_EXT_BIN${NC}\n"

# ── 2. Run ────────────────────────────────────────────────────────────────────

echo -e "${YELLOW}[3/4] Running implementations...${NC}\n"

echo -e "${CYAN}--- Traditional Output (demo) ---${NC}"
"$TRAD_BIN" demo
echo ""

echo -e "${CYAN}--- FaaS Output (demo) ---${NC}"
"$FAAS_BIN" demo
echo ""

echo -e "${CYAN}--- Feature Extension: Traditional ---${NC}"
"$TRAD_EXT_BIN"
echo ""

echo -e "${CYAN}--- Feature Extension: FaaS ---${NC}"
"$FAAS_EXT_BIN"
echo ""

# ── 3. Performance Profiling ──────────────────────────────────────────────────

echo -e "${YELLOW}[4/4] Performance Profiling...${NC}\n"

RESULTS_DIR="profiling_results"
mkdir -p "$RESULTS_DIR"

# Helper: run perf if available, otherwise use /usr/bin/time
run_profile() {
    local label="$1"
    local binary="$2"
    local out_prefix="$3"
    echo -e "${CYAN}--- $label ---${NC}"
    echo "Benchmark workload: $BENCH_RUNS iterations in-process"

    if command -v perf &>/dev/null; then
        # NOTE: KVM/virtualized guests typically expose only a few hardware
        # PMU counter slots. Requesting too many hardware events in one
        # `perf stat` call can cause multiplexing to evict one of them
        # entirely (observed: "cycles" reading exactly 0). Splitting into two
        # smaller runs keeps each within the available counter budget.
        perf stat -r 5 -e cycles,instructions,context-switches \
               "$binary" benchmark > /dev/null 2> "$RESULTS_DIR/${out_prefix}_perf_stat.txt"
        cat "$RESULTS_DIR/${out_prefix}_perf_stat.txt"

        perf stat -r 5 -e branches,branch-misses,cache-references,cache-misses \
               "$binary" benchmark > /dev/null 2> "$RESULTS_DIR/${out_prefix}_perf_stat_cache.txt"
        cat "$RESULTS_DIR/${out_prefix}_perf_stat_cache.txt"

        # Software events (page-faults, migrations) are always available even
        # when the hardware PMU is limited/virtualized. These directly probe
        # memory-allocation and scheduler behavior -- e.g. testing whether
        # FaaS's per-call std::map<string,string> allocations show up as more
        # minor page faults than Traditional's in-process method calls.
        perf stat -r 5 -e page-faults,minor-faults,major-faults,cpu-migrations \
               "$binary" benchmark > /dev/null 2> "$RESULTS_DIR/${out_prefix}_perf_stat_mem.txt"
        cat "$RESULTS_DIR/${out_prefix}_perf_stat_mem.txt"

        # Optional syscall summary if strace exists
        if command -v strace &>/dev/null; then
            strace -c "$binary" benchmark > /dev/null 2> "$RESULTS_DIR/${out_prefix}_syscalls.txt"
            echo "\nTop syscalls:"
            head -20 "$RESULTS_DIR/${out_prefix}_syscalls.txt"
        fi
    fi

    if [ -x /usr/bin/time ]; then
        /usr/bin/time -f "real=%e user=%U sys=%S maxrss=%MKB" \
            "$binary" benchmark > /dev/null 2> "$RESULTS_DIR/${out_prefix}_time.txt"
        cat "$RESULTS_DIR/${out_prefix}_time.txt"
    else
        echo "Warning: /usr/bin/time not found."
    fi

    echo ""
}

run_profile "Traditional" "$TRAD_BIN" "traditional"
run_profile "FaaS" "$FAAS_BIN" "faas"

# Consolidated summary file (mirrors HW1's results/summary.txt) so all
# metrics for both architectures can be reviewed/copied from one place.
{
    printf "# HW2 Profiling Summary\n# %s\n\n" "$(date)"
    printf "=== Traditional: core (cycles/instructions/context-switches) ===\n"
    cat "$RESULTS_DIR/traditional_perf_stat.txt"
    printf "\n=== Traditional: branches/cache ===\n"
    cat "$RESULTS_DIR/traditional_perf_stat_cache.txt"
    printf "\n=== Traditional: page-faults/migrations ===\n"
    cat "$RESULTS_DIR/traditional_perf_stat_mem.txt"
    printf "\n=== Traditional: /usr/bin/time ===\n"
    cat "$RESULTS_DIR/traditional_time.txt"

    printf "\n\n=== FaaS: core (cycles/instructions/context-switches) ===\n"
    cat "$RESULTS_DIR/faas_perf_stat.txt"
    printf "\n=== FaaS: branches/cache ===\n"
    cat "$RESULTS_DIR/faas_perf_stat_cache.txt"
    printf "\n=== FaaS: page-faults/migrations ===\n"
    cat "$RESULTS_DIR/faas_perf_stat_mem.txt"
    printf "\n=== FaaS: /usr/bin/time ===\n"
    cat "$RESULTS_DIR/faas_time.txt"
} > "$RESULTS_DIR/summary.txt"

echo -e "${GREEN}Saved profiling outputs under: $RESULTS_DIR${NC}"
echo -e "${GREEN}Consolidated summary: $RESULTS_DIR/summary.txt${NC}"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  All steps complete.${NC}"
echo -e "${GREEN}========================================${NC}"

