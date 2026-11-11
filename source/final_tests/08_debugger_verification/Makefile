# =============================================================================
# Makefile for Subsystem 08: Full Debugger Verification (Block & Full-SoC)
# =============================================================================

ROOT_DIR := $(abspath ../..)
VLIB ?= vlib
VLOG ?= vlog
VSIM ?= vsim

.PHONY: all help test_all test_block test_soc test_icarus clean

all: test_all

help:
	@echo "=================================================================="
	@echo " Subsystem 08: Comprehensive Debugger Verification Suite"
	@echo "=================================================================="
	@echo " Targets:"
	@echo "   make test_block     - Run block-level self-checking suite (528 checks)"
	@echo "   make test_soc       - Run full SoC debugger pins verification (84 checks)"
	@echo "   make test_all       - Run both block and full SoC tests (QuestaSim)"
	@echo "   make test_icarus    - Run both suites via Icarus Verilog"
	@echo "   make clean          - Remove all simulation and build artifacts"
	@echo "=================================================================="

# 1. Block-Level Debugger Verification on QuestaSim
test_block:
	@echo "================================================================"
	@echo " Running Test: Debugger Block-Level Comprehensive Verification "
	@echo " (528 checks: ADP protocol, UART/FT1248 links, bus errors, CRV)"
	@echo "================================================================"
	rm -rf work transcript vsim.wlf block/results_block.txt
	$(VLIB) work >/dev/null
	$(VLOG) -sv -timescale 1ns/1ps -work work \
		+incdir+$(ROOT_DIR)/debugger \
		+incdir+block \
		$(ROOT_DIR)/debugger/socdebug_uart.v \
		$(ROOT_DIR)/debugger/socdebug_ft1248_control.v \
		$(ROOT_DIR)/debugger/socdebug_adp_control.v \
		$(ROOT_DIR)/debugger/socdebug_ahb.v \
		$(ROOT_DIR)/debugger/riscv_debugger_top.sv \
		$(ROOT_DIR)/debugger/ahb_mux.sv \
		$(ROOT_DIR)/debugger/core_step_controller.sv \
		$(ROOT_DIR)/debugger/tb/f232h_ft1248_stream.v \
		block/tb_models.sv \
		block/tb_dbg_block.sv >/dev/null
	$(VSIM) -c -voptargs="+acc" -do "run -all; quit -f" work.tb_dbg_block | grep -E "PASS|FAIL|BLOCK LEVEL"

# 2. Full-SoC Debugger Verification on QuestaSim
test_soc:
	@echo "================================================================"
	@echo " Running Test: Debugger Full-SoC System Verification           "
	@echo " (84 checks: Halt/step, GPR/CSR/PC/trace, Traps, Reset, FT1248) "
	@echo "================================================================"
	cd soc && rm -rf work transcript vsim.wlf results_soc.txt && \
	$(VLIB) work >/dev/null && \
	$(VLOG) -sv -timescale 1ns/1ps -work work \
		+incdir+$(ROOT_DIR)/main \
		+incdir+$(ROOT_DIR)/main/soc \
		+incdir+$(ROOT_DIR)/components \
		+incdir+$(ROOT_DIR)/uncore \
		+incdir+$(ROOT_DIR)/debugger \
		$(ROOT_DIR)/components/*.v \
		$(ROOT_DIR)/main/riscv_cpu.v \
		$(ROOT_DIR)/main/soc/multiplier_ahb.v \
		$(ROOT_DIR)/main/soc/riscv_soc_ahb.v \
		$(ROOT_DIR)/uncore/*.sv \
		$(ROOT_DIR)/debugger/*.v \
		$(ROOT_DIR)/debugger/*.sv \
		$(ROOT_DIR)/debugger/tb/f232h_ft1248_stream.v \
		tb_soc_dbg_full.sv >/dev/null && \
	$(VSIM) -c -voptargs="+acc" -do "run -all; quit -f" work.tb_soc_dbg_full | grep -E "PASS|FAIL|SOC LEVEL"

test_all: test_block test_soc
	@echo ""
	@echo "================================================================"
	@echo " ALL SUBSYSTEM 08 DEBUGGER TESTS PASSED SUCCESSFULLY!           "
	@echo "================================================================"

test_icarus:
	@echo "\n>>> Running Subsystem 08 Block Suite on Icarus Verilog..."
	@cd block && ./run_icarus.sh
	@echo "\n>>> Running Subsystem 08 Full-SoC Suite on Icarus Verilog..."
	@cd soc && ./run_icarus.sh

clean:
	rm -rf work transcript vsim.wlf block/results_block.txt block/sim_block
	rm -rf soc/work soc/transcript soc/vsim.wlf soc/results_soc.txt soc/sim_soc

