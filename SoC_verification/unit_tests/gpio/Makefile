# =============================================================================
# Makefile: GPIO IP Unit Testbench
# Simulator: QuestaSim (vlib, vlog, vsim)
# =============================================================================

TOP_DIR := ../..
RTL_DIR := $(TOP_DIR)/rtl
VIP_DIR := $(TOP_DIR)/vip

VLIB ?= vlib
VLOG ?= vlog
VSIM ?= vsim

TEST ?= gpio_unit_test
GUI  ?= 0

VLOG_ARGS = -sv -timescale 1ns/1ps \
	+incdir+$(VIP_DIR)/apb_vip \
	+incdir+$(VIP_DIR)/gpio_vip \
	+incdir+$(RTL_DIR)/uncore \
	+incdir+.

VSIM_ARGS = -c -voptargs="+acc" +UVM_TESTNAME=$(TEST) +UVM_VERBOSITY=UVM_LOW

all: run

compile:
	rm -rf work transcript vsim.wlf
	$(VLIB) work
	$(VLOG) $(VLOG_ARGS) \
		$(VIP_DIR)/apb_vip/apb_if.sv \
		$(VIP_DIR)/apb_vip/apb_pkg.sv \
		$(VIP_DIR)/gpio_vip/gpio_if.sv \
		$(VIP_DIR)/gpio_vip/gpio_pkg.sv \
		$(RTL_DIR)/uncore/gpio_apb.sv \
		tb_gpio_unit.sv

run: compile
	$(VSIM) $(VSIM_ARGS) -do "run -all; quit -f" work.tb_gpio_unit

clean:
	rm -rf work transcript vsim.wlf *.log

