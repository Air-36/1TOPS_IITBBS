#-----------------------------------------------------------------------------
# 1TOPS SoC - ZCU102 FPGA Flow Makefile
# Same flow and target names as the nanosoc ZCU102 flow (makefile.fpga):
#   code -> build_fpga -> stream_remote (program over the remote hw_server)
# Part selection comes from makefile.targets (unchanged from nanosoc).
#
# Run on the (remote) server that has Vivado. The ZCU102 is on the bench, its JTAG USB
# connected to the machine running hw_server ($(HW_SERVER)).
#   make build_fpga                 # bitstream -> output/tops_soc_zcu102.bit (+ .ltx for the ILA)
#   make stream_remote              # program the ZCU102 via $(HW_SERVER)
#   make code / make rom            # build software / write the boot ROM into the RTL
#   make sim                        # iverilog check of the RTL top (no Vivado needed)
#-----------------------------------------------------------------------------

FPGA ?= zcu102
include makefile.targets

ZCU_DIR          := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
REPO_DIR         := $(abspath $(ZCU_DIR)/../..)
SOFTWARE_DIR     := $(REPO_DIR)/software
RUN_DIR          := $(ZCU_DIR)/build
OUTPUT_DIR       := $(ZCU_DIR)/output
DESIGN_NAME      ?= tops_soc_zcu102

# Build options (passed to build_zcu102.tcl)
CLK_SRC           ?= CLK125        # CLK125 (125 MHz, G21/F21) or SI570 (300 MHz, AL8/AL7)
ENABLE_ILA        ?= 1
JOBS              ?= 8
ALLOW_TIMING_FAIL ?= 0

# Remote hardware server (same address/port as the nanosoc flow)
# Lab PC running hw_server (the PC the ZCU102 JTAG USB J2 is plugged into). Change it here, or
# override per run: make stream_remote HW_SERVER=<ip>:3121  (or export HW_SERVER=<ip>:3121).
HW_SERVER        ?= 10.10.92.226:3121
BITFILE          ?= $(OUTPUT_DIR)/$(DESIGN_NAME).bit

.PHONY: help code rom build_fpga build_only stream_remote sim clean_fpga clean_fpga_all

help:
	@echo "1TOPS SoC on $(BOARD_NAME) ($(XILINX_PART))"
	@echo "  make code           - build software (boot ROMs, tests)"
	@echo "  make rom            - write the internal boot ROM into source/uncore/rom_ahb.sv (RISC-V toolchain)"
	@echo "  make build_fpga     - clean + Vivado build -> $(OUTPUT_DIR)"
	@echo "  make stream_remote  - program over hw_server $(HW_SERVER) (HW_SERVER=host:port to override)"
	@echo "  make sim            - iverilog simulation of the ZCU102 top (no Vivado needed)"
	@echo "  make clean_fpga     - remove build/ and output/"

# Compile software: boot ROMs + test programs (as `make code` in the nanosoc flow)
code:
	@echo Compiling Firmware
	@$(MAKE) -C $(SOFTWARE_DIR) all

# Write the internal boot ROM into the RTL case table (explicit: edits RTL source)
rom:
	@$(MAKE) -C $(SOFTWARE_DIR) rom

# Synthesise and implement the bitfile
build_only:
	@echo Building 1TOPS SoC for $(BOARD_NAME)
	@mkdir -p $(RUN_DIR)
	@cd $(RUN_DIR); FPGA_PART=$(XILINX_PART) CLK_SRC=$(strip $(CLK_SRC)) ENABLE_ILA=$(ENABLE_ILA) JOBS=$(JOBS) \
	  ALLOW_TIMING_FAIL=$(ALLOW_TIMING_FAIL) \
	  vivado -mode batch -source $(ZCU_DIR)/build_zcu102.tcl -log vivado.log -journal vivado.jou
	@echo Built 1TOPS SoC: $(BITFILE)

build_fpga: clean_fpga build_only

# Stream the bitstream over the remote hw_server (hw_server.tcl unchanged from the nanosoc flow)
stream_remote:
	@test -f $(BITFILE) || { echo "ERROR: $(BITFILE) not found - run make build_fpga first"; exit 1; }
	@mkdir -p $(RUN_DIR)
	@export HW_SERVER=$(HW_SERVER) BITFILE=$(BITFILE); \
	cd $(RUN_DIR); vivado -mode batch -source $(ZCU_DIR)/hw_server.tcl -log stream.log -journal stream.jou

# RTL check of the top-level wrapper with iverilog
sim:
	@$(ZCU_DIR)/sim/run_sim.sh

clean_fpga:
	@echo Cleaning previous runs of $(BOARD_NAME)
	@rm -rf $(RUN_DIR) $(OUTPUT_DIR)

clean_fpga_all: clean_fpga
	@$(MAKE) -C $(SOFTWARE_DIR) clean
