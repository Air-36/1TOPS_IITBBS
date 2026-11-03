#!/bin/bash
# ==============================================================================
# Script: run_build.sh
# Purpose: Execute Vivado project generation inside isolated fpga/build directory
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

echo "=================================================================="
echo " Building 1TOPS SoC Vivado Project"
echo " Isolated Build Directory: $BUILD_DIR"
echo " TCL Script:                $SCRIPT_DIR/build_fpga.tcl"
echo "=================================================================="

# Check for Vivado availability; if not present, check module environment
if ! command -v vivado &> /dev/null; then
    if command -v module &> /dev/null || [ -n "$MODULESHOME" ]; then
        echo "[INFO] Vivado not in PATH. Attempting to load Vivado module..."
        module load xilinx/vivado 2>/dev/null || module load vivado 2>/dev/null || true
    fi
fi

if ! command -v vivado &> /dev/null; then
    echo "[WARNING] Vivado binary not found in current environment."
    echo "[INFO] Try: module avail && module load <vivado-module>"
    echo "[INFO] TCL script is ready at: $SCRIPT_DIR/build_fpga.tcl"
    exit 1
fi

vivado -mode batch -source "$SCRIPT_DIR/build_fpga.tcl" -log "$BUILD_DIR/vivado.log" -journal "$BUILD_DIR/vivado.jou" "$@"
