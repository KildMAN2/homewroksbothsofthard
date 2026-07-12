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
        perf stat -r 5 -e cycles,instructions,cache-misses,context-switches \
               "$binary" benchmark > /dev/null 2> "$RESULTS_DIR/${out_prefix}_perf_stat.txt"
        cat "$RESULTS_DIR/${out_prefix}_perf_stat.txt"

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

echo -e "${GREEN}Saved profiling outputs under: $RESULTS_DIR${NC}"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  All steps complete.${NC}"
echo -e "${GREEN}========================================${NC}"

