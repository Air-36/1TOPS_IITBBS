# =============================================================================
# Makefile: Multiplier AHB Slave Unit Testbench
# Simulator: QuestaSim (vlib, vlog, vsim)
# =============================================================================

TOP_DIR := ../..
RTL_DIR := $(TOP_DIR)/rtl
VIP_DIR := $(TOP_DIR)/vip

VLIB ?= vlib
VLOG ?= vlog
VSIM ?= vsim

TEST ?= multiplier_unit_test

VLOG_ARGS = -sv -timescale 1ns/1ps \
	+incdir+$(VIP_DIR)/ahb_lite_vip \
	+incdir+$(RTL_DIR)/main/soc \
	+incdir+.

VSIM_ARGS = -c -voptargs="+acc" +UVM_TESTNAME=$(TEST) +UVM_VERBOSITY=UVM_LOW

all: run

compile:
	rm -rf work transcript vsim.wlf
	$(VLIB) work
	$(VLOG) $(VLOG_ARGS) \
		$(VIP_DIR)/ahb_lite_vip/ahb_lite_if.sv \
		$(VIP_DIR)/ahb_lite_vip/ahb_lite_pkg.sv \
		$(RTL_DIR)/main/soc/multiplier_ahb.v \
		tb_multiplier_unit.sv

run: compile
	$(VSIM) $(VSIM_ARGS) -do "run -all; quit -f" work.tb_multiplier_unit

clean:
	rm -rf work transcript vsim.wlf *.log

