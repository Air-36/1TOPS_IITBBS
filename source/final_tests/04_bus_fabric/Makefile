# =============================================================================
# Makefile for Subsystem 04: AMBA AHB/APB Bus Fabric & Arbiters
# =============================================================================

ROOT_DIR := $(abspath ../..)
VLIB ?= vlib
VLOG ?= vlog
VSIM ?= vsim

.PHONY: all test_all test_ahb_mux test_apb_bridge clean

all: test_all

test_ahb_mux:
	@echo "================================================================"
	@echo " Running Constrained-Random Test: 2-Master AHB-Lite Arbiter/Mux "
	@echo "================================================================"
	rm -rf work transcript vsim.wlf
	$(VLIB) work
	$(VLOG) -sv -work work $(ROOT_DIR)/debugger/ahb_mux.sv
	$(VLOG) -sv -work work tb/tb_ahb_mux_crv.sv
	$(VSIM) -c -do "run -all; quit -f" work.tb_ahb_mux_crv

test_apb_bridge:
	@echo "================================================================"
	@echo " Running Constrained-Random Test: AHB-Lite to APB Bridge        "
	@echo "================================================================"
	rm -rf work transcript vsim.wlf
	$(VLIB) work
	$(VLOG) -sv -work work $(ROOT_DIR)/uncore/ahbapbbridge.sv
	$(VLOG) -sv -work work tb/tb_ahb_apb_bridge_crv.sv
	$(VSIM) -c -do "run -all; quit -f" work.tb_ahb_apb_bridge_crv

test_all: test_ahb_mux test_apb_bridge
	@echo ""
	@echo "================================================================"
	@echo " ALL BUS FABRIC VERIFICATION TESTS PASSED SUCCESSFULLY!         "
	@echo "================================================================"

clean:
	rm -rf work transcript vsim.wlf
