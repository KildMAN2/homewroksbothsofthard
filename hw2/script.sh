#!/bin/bash
# HW2 — Hotel Management System
# Build, Run, and Performance Profiling Script
# Usage: bash script.sh

set -e

TRAD_DIR="Traditional"
FAAS_DIR="FaaS"
TRAD_BIN="$TRAD_DIR/hotel_traditional"
FAAS_BIN="$FAAS_DIR/hotel_faas"
TRAD_EXT_BIN="$TRAD_DIR/hotel_trad_extension"
FAAS_EXT_BIN="$FAAS_DIR/hotel_faas_extension"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  HW2: Hotel Management System${NC}"
echo -e "${CYAN}========================================${NC}\n"

# ── 1. Build ──────────────────────────────────────────────────────────────────

echo -e "${YELLOW}[1/4] Building Traditional architecture...${NC}"
g++ -O2 -std=c++14 -o "$TRAD_BIN"     "$TRAD_DIR/main.cpp"
g++ -O2 -std=c++14 -o "$TRAD_EXT_BIN" "$TRAD_DIR/feature_extension.cpp"
echo -e "${GREEN}      Built: $TRAD_BIN${NC}"

echo -e "${YELLOW}[2/4] Building FaaS architecture...${NC}"
g++ -O2 -std=c++14 -o "$FAAS_BIN"     "$FAAS_DIR/main.cpp"
g++ -O2 -std=c++14 -o "$FAAS_EXT_BIN" "$FAAS_DIR/feature_extension.cpp"
echo -e "${GREEN}      Built: $FAAS_BIN${NC}\n"

# ── 2. Run ────────────────────────────────────────────────────────────────────

echo -e "${YELLOW}[3/4] Running implementations...${NC}\n"

echo -e "${CYAN}--- Traditional Output ---${NC}"
"$TRAD_BIN"
echo ""

echo -e "${CYAN}--- FaaS Output ---${NC}"
"$FAAS_BIN"
echo ""

echo -e "${CYAN}--- Feature Extension: Traditional ---${NC}"
"$TRAD_EXT_BIN"
echo ""

echo -e "${CYAN}--- Feature Extension: FaaS ---${NC}"
"$FAAS_EXT_BIN"
echo ""

# ── 3. Performance Profiling ──────────────────────────────────────────────────

echo -e "${YELLOW}[4/4] Performance Profiling...${NC}\n"

# Helper: run perf if available, otherwise use /usr/bin/time
run_profile() {
    local label="$1"
    local binary="$2"
    echo -e "${CYAN}--- $label ---${NC}"
    if command -v perf &>/dev/null; then
        perf stat -e cycles,instructions,cache-misses,context-switches \
             "$binary" > /dev/null 2>&1 || \
        perf stat "$binary" > /dev/null
    elif command -v time &>/dev/null; then
        /usr/bin/time -v "$binary" > /dev/null 2>&1 || \
        { echo "  (timing with shell built-in)"; time "$binary" > /dev/null; }
    else
        echo "  perf and /usr/bin/time not available; timing with date:"
        START=$(date +%s%N)
        "$binary" > /dev/null
        END=$(date +%s%N)
        echo "  Elapsed: $(( (END - START) / 1000000 )) ms"
    fi
    echo ""
}

# Run each binary 3 times to get stable measurements
for RUN in 1 2 3; do
    echo -e "${YELLOW}  Pass $RUN / 3${NC}"
    run_profile "Traditional (pass $RUN)" "$TRAD_BIN"
    run_profile "FaaS        (pass $RUN)" "$FAAS_BIN"
done

# Full perf record (generates perf.data for deeper analysis)
if command -v perf &>/dev/null; then
    echo -e "${CYAN}--- Detailed perf record (Traditional) ---${NC}"
    perf record -o perf_traditional.data -g "$TRAD_BIN" > /dev/null 2>&1
    perf report -i perf_traditional.data --stdio 2>/dev/null | head -40

    echo -e "${CYAN}--- Detailed perf record (FaaS) ---${NC}"
    perf record -o perf_faas.data -g "$FAAS_BIN" > /dev/null 2>&1
    perf report -i perf_faas.data --stdio 2>/dev/null | head -40
fi

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  All steps complete.${NC}"
echo -e "${GREEN}========================================${NC}"

