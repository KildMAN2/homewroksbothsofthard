#!/usr/bin/env bash
# Compile and simulate the pyflate accelerator RTL.
#
# Tries ModelSim (vlog/vsim) first, then falls back to Icarus Verilog
# (iverilog + vvp), then Verilator. Writes per-testbench logs into
# subPyflate/hw/results/ and appends a summary to SIMULATION_RESULTS.txt.
#
# Usage:
#   bash subPyflate/hw/run_sim.sh                # all three testbenches
#   bash subPyflate/hw/run_sim.sh tb_huff_lut
set -euo pipefail

HW_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RTL_DIR="$HW_DIR/rtl"
TB_DIR="$HW_DIR/tb"
RESULTS_DIR="$HW_DIR/results"
mkdir -p "$RESULTS_DIR"

TBS=("tb_huff_lut" "tb_bit_shifter" "tb_huffman_decoder")
if [ "$#" -gt 0 ]; then
    TBS=("$@")
fi

RTL_FILES=("$RTL_DIR/huff_lut.sv" "$RTL_DIR/bit_shifter.sv" "$RTL_DIR/huffman_decoder.sv")

pick_simulator() {
    if command -v vsim >/dev/null 2>&1 && command -v vlog >/dev/null 2>&1; then
        echo "modelsim"
    elif command -v iverilog >/dev/null 2>&1 && command -v vvp >/dev/null 2>&1; then
        echo "iverilog"
    elif command -v verilator >/dev/null 2>&1; then
        echo "verilator"
    else
        echo "none"
    fi
}

SIM="$(pick_simulator)"
[ "$SIM" = "none" ] && { echo "[run_sim] no SystemVerilog simulator found (vsim/iverilog/verilator)"; exit 3; }
echo "[run_sim] simulator: $SIM"

sim_modelsim() {
    local tb="$1"
    local log="$RESULTS_DIR/sim_${tb}.log"
    (
        cd "$HW_DIR"
        vlib -type directory work >/dev/null 2>&1 || true
        vlib work >/dev/null 2>&1 || true
        vlog -sv "${RTL_FILES[@]}" "$TB_DIR/${tb}.sv"
        vsim -c -do "run -all; quit -f" "work.${tb}"
    ) 2>&1 | tee "$log"
}

sim_iverilog() {
    local tb="$1"
    local log="$RESULTS_DIR/sim_${tb}.log"
    local exe="$RESULTS_DIR/${tb}.vvp"
    (
        iverilog -g2012 -o "$exe" "${RTL_FILES[@]}" "$TB_DIR/${tb}.sv"
        vvp "$exe"
    ) 2>&1 | tee "$log"
}

sim_verilator() {
    local tb="$1"
    local log="$RESULTS_DIR/sim_${tb}.log"
    (
        verilator --binary --top-module "$tb" \
            -Wno-fatal --timing \
            "${RTL_FILES[@]}" "$TB_DIR/${tb}.sv" -o "${tb}_sim" \
            --Mdir "$RESULTS_DIR/obj_${tb}"
        "$RESULTS_DIR/obj_${tb}/${tb}_sim"
    ) 2>&1 | tee "$log"
}

run_one() {
    local tb="$1"
    echo
    echo "[run_sim] === $tb ==="
    case "$SIM" in
        modelsim)  sim_modelsim  "$tb" ;;
        iverilog)  sim_iverilog  "$tb" ;;
        verilator) sim_verilator "$tb" ;;
    esac
}

for tb in "${TBS[@]}"; do
    run_one "$tb"
done

# Rewrite SIMULATION_RESULTS.txt from the latest logs.
SUMMARY="$RESULTS_DIR/SIMULATION_RESULTS.txt"
{
    echo "Pyflate Accelerator - Simulation Results"
    echo "========================================"
    echo
    echo "Simulator: $SIM"
    echo "Date of run: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo
    echo "RTL files:"
    for f in "${RTL_FILES[@]}"; do
        echo "  $f"
    done
    echo
    echo "Testbenches:"
    for tb in "${TBS[@]}"; do
        log="$RESULTS_DIR/sim_${tb}.log"
        result_line="$(grep -E "RESULT:" "$log" | tail -n 1 || true)"
        checks_line="$(grep -E "TESTS: checks=" "$log" | tail -n 1 || true)"
        echo
        echo "  $tb"
        echo "    log:     $log"
        echo "    checks:  ${checks_line:-N/A}"
        echo "    verdict: ${result_line:-N/A}"
    done
    echo
    echo "Notes:"
    echo "  - Reference values in each testbench are computed in-testbench;"
    echo "    the DUT's output is checked directly against them."
    echo "  - No synthesis was run. No area/frequency/power numbers are"
    echo "    claimed; see subPyflate/docs/13_hardware_performance.md for"
    echo "    ESTIMATE-labeled projections."
} > "$SUMMARY"

echo
echo "[run_sim] summary written to $SUMMARY"
