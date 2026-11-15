#!/usr/bin/env bash
# ==============================================================================
# sim_step_and_clkdiv.sh
# Automated Vivado XSIM Test Runner for 1TOPS SoC Debugger
# Verifies:
#   1. Core Instruction-Step and Clock-Cycle Step FSM Controller
#   2. Reconfigurable UART & FT1248 Clock Dividers
#   3. Dual-Protocol (UART & FT1248) Stream Multiplexing & Isolation
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build"
if [ -d "${SCRIPT_DIR}/../source" ]; then
    SOURCE_DIR="$(cd "${SCRIPT_DIR}/../source" && pwd)"
else
    SOURCE_DIR="$(cd "${SCRIPT_DIR}/../../source" && pwd)"
fi

mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

echo "=============================================================================="
echo "Starting SoCDebug Step & Clock Division Simulation (Vivado XSIM)"
echo "Working Directory: ${BUILD_DIR}"
echo "Source Directory:  ${SOURCE_DIR}"
echo "=============================================================================="

# Ensure Vivado environment is available
if ! command -v xvlog &> /dev/null; then
    if [ -f "/etc/profile" ]; then
        source /etc/profile
    fi
    if command -v module &> /dev/null; then
        module use /cad/modulefiles 2>/dev/null || true
        module load xilinx/vivado/2024.2 2>/dev/null || module load xilinx/vivado 2>/dev/null || module load vivado 2>/dev/null || true
    fi
fi

if ! command -v xvlog &> /dev/null; then
    if [ -f "/home/ganesh/Xilinx/2025.2/Vivado/settings64.sh" ]; then
        source "/home/ganesh/Xilinx/2025.2/Vivado/settings64.sh"
    elif [ -f "/tools/Xilinx/Vivado/2025.2/settings64.sh" ]; then
        source "/tools/Xilinx/Vivado/2025.2/settings64.sh"
    else
        echo "[-] Error: Vivado (xvlog/xelab/xsim) not found in PATH."
        echo "[-] Please try: module avail && module load <vivado-module>"
        exit 1
    fi
fi

# 1. Compile SystemVerilog Sources
echo "[1/3] Compiling SystemVerilog and Verilog Sources with xvlog..."
xvlog -sv \
  -i "${SOURCE_DIR}/debugger" \
  "${SOURCE_DIR}/debugger/socdebug_adp_control.v" \
  "${SOURCE_DIR}/debugger/socdebug_ahb.v" \
  "${SOURCE_DIR}/debugger/socdebug_uart.v" \
  "${SOURCE_DIR}/debugger/socdebug_ft1248_control.v" \
  "${SOURCE_DIR}/debugger/core_step_controller.sv" \
  "${SOURCE_DIR}/debugger/core_debug_ahb.v" \
  "${SOURCE_DIR}/debugger/riscv_debugger_top.sv" \
  "${SOURCE_DIR}/debugger/ahb_mux.sv" \
  "${SOURCE_DIR}/main/soc/multiplier_ahb.v" \
  "${SOURCE_DIR}/debugger/tb/f232h_ft1248_stream.v" \
  "${SOURCE_DIR}/debugger/tb/tb_debugger.sv"

# 2. Elaborate Design
echo "[2/3] Elaborating simulation snapshot with xelab..."
xelab --timescale 1ns/1ps -debug typical tb_debugger -s tb_debugger_sim

# 3. Execute Simulation
echo "[3/3] Running simulation in xsim batch mode..."
xsim tb_debugger_sim -runall

echo "=============================================================================="
echo "[SUCCESS] Simulation completed successfully in ${BUILD_DIR}!"
echo "=============================================================================="
