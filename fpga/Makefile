# =============================================================================
# Basys 3 (xc7a35t): simulation, bitstream, remote programming. ZCU102: see zcu102/Makefile.
#   make sim             iverilog check of the board top (sim/tb_basys3_top.sv)
#   make build_fpga      Vivado: project -> bitstream -> output/tops_soc_basys3.bit (+ timing check)
#   make stream_remote   program the Basys 3 through hw_server $(HW_SERVER)
# =============================================================================
FPGA_DIR  := $(CURDIR)
BITFILE   ?= $(FPGA_DIR)/output/tops_soc_basys3.bit
# Lab PC running hw_server (the PC the Basys 3 USB is plugged into). Override: make stream_remote HW_SERVER=<ip>:3121
HW_SERVER ?= 10.10.92.226:3121
JOBS      ?= 8

.PHONY: sim build_fpga stream_remote clean_fpga

sim:
	@$(FPGA_DIR)/sim/run_sim.sh

build_fpga:
	@mkdir -p $(FPGA_DIR)/build
	@cd $(FPGA_DIR)/build && JOBS=$(JOBS) vivado -mode batch -source $(FPGA_DIR)/build_basys3_bitstream.tcl \
	   -log basys3_build.log -journal basys3_build.jou
	@echo Built 1TOPS SoC: $(BITFILE)

stream_remote:
	@test -f $(BITFILE) || { echo "ERROR: $(BITFILE) not found - run make build_fpga first"; exit 1; }
	@mkdir -p $(FPGA_DIR)/build
	@cd $(FPGA_DIR)/build && BITFILE=$(BITFILE) HW_SERVER=$(HW_SERVER) DEVICE='xc7a35t*' \
	   vivado -mode batch -source $(FPGA_DIR)/hw_program.tcl -log program.log -journal program.jou

clean_fpga:
	@rm -rf $(FPGA_DIR)/build $(FPGA_DIR)/output $(FPGA_DIR)/sim/build
