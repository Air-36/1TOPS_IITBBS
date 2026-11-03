#!/bin/bash
# ==============================================================================
# Script: run.sh
# Purpose: Run HWSTRB & Bus Ownership Verification Regression
# Usage: ./run.sh [/path/to/repo]
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${1:-$SCRIPT_DIR}"

# Resolve to source root if a parent dir was passed
if [ -d "$TARGET_DIR/source" ]; then
    TARGET_DIR="$TARGET_DIR/source"
fi

TB_DIR="$TARGET_DIR/final_tests/06_debugger_subsystem"
TB_FILE="$TB_DIR/tb/tb_hwstrb_regression.sv"

if [ ! -f "$TB_FILE" ]; then
    echo "[ERROR] Regression testbench not found at $TB_FILE"
    exit 1
fi

echo "=================================================================="
echo " Running Regression Suite on: $TARGET_DIR"
echo " Testbench: $TB_FILE"
echo "=================================================================="

# Check for QuestaSim / ModelSim / Verilator modules if not currently in PATH
if ! command -v vsim &> /dev/null && ! command -v verilator &> /dev/null; then
    if command -v module &> /dev/null || [ -n "$MODULESHOME" ]; then
        module load questasim 2>/dev/null || module load modelsim 2>/dev/null || module load verilator 2>/dev/null || true
    fi
fi

# Check for QuestaSim/ModelSim
if command -v vsim &> /dev/null && command -v vlog &> /dev/null; then
    echo "[INFO] Running regression using QuestaSim..."
    cd "$TB_DIR"
    rm -rf work transcript vsim.wlf
    vlib work >/dev/null
    vlog -sv -timescale 1ns/1ps -work work \
        +incdir+"$TARGET_DIR/main" \
        +incdir+"$TARGET_DIR/main/soc" \
        +incdir+"$TARGET_DIR/components" \
        +incdir+"$TARGET_DIR/uncore" \
        +incdir+"$TARGET_DIR/debugger" \
        "$TARGET_DIR/components/"*.v \
        "$TARGET_DIR/main/"*.v \
        "$TARGET_DIR/main/soc/"*.v \
        "$TARGET_DIR/uncore/"*.sv \
        "$TARGET_DIR/debugger/"*.v \
        "$TARGET_DIR/debugger/"*.sv \
        "$TB_FILE" >/dev/null

    vsim -c -voptargs="+acc" -do "run -all; quit -f" work.tb_hwstrb_regression | grep -A 10 "REGRESSION TEST RESULTS"
    exit 0
fi

# Fallback: Check for Verilator
if command -v verilator &> /dev/null; then
    echo "[INFO] Running regression using Verilator..."
    cd "$TB_DIR"
    verilator --binary -sv --trace \
        +incdir+"$TARGET_DIR/main" \
        +incdir+"$TARGET_DIR/main/soc" \
        +incdir+"$TARGET_DIR/components" \
        +incdir+"$TARGET_DIR/uncore" \
        +incdir+"$TARGET_DIR/debugger" \
        "$TARGET_DIR/components/"*.v \
        "$TARGET_DIR/main/"*.v \
        "$TARGET_DIR/main/soc/"*.v \
        "$TARGET_DIR/uncore/"*.sv \
        "$TARGET_DIR/debugger/"*.v \
        "$TARGET_DIR/debugger/"*.sv \
        "$TB_FILE" --top-module tb_hwstrb_regression -o Vtb_hwstrb_regression
    ./obj_dir/Vtb_hwstrb_regression
    exit 0
fi

echo "[ERROR] Neither QuestaSim (vsim/vlog) nor Verilator found in PATH!"
exit 1
