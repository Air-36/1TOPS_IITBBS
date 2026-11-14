# =============================================================================
# Makefile for Subsystem 09: SPI Boot Flow, End to End
# =============================================================================
# The real SoC (default reset addresses) + the generated boot ROM + make_image.py streams +
# an SPI partner model (ideal, or the Pi 4 timing model). See README.md.
#
#   make test_all              all scenarios (QuestaSim, like subsystems 01-07)
#   make test_all SIM=icarus   same with Icarus Verilog
#   make s1 ... s8b            one scenario
#   make streams               only build the test program and the boot streams
#
# Needs: the boot ROM regenerated (make -C software rom), a RISC-V GCC (RISCV_PREFIX),
#        python3 with pyelftools.
# =============================================================================

ROOT_DIR := $(abspath ../..)
REPO_DIR := $(abspath ../../..)
SW_DIR   := $(REPO_DIR)/software
BUILD    := $(CURDIR)/build

SIM  ?= questa
VLIB ?= vlib
VLOG ?= vlog
VSIM ?= vsim
IVERILOG ?= iverilog
VVP      ?= vvp
PYTHON   ?= python3

RISCV_BIN = /opt/riscv/bin
ifneq ($(wildcard $(RISCV_BIN)/riscv64-unknown-elf-gcc),)
  RISCV_PREFIX ?= $(RISCV_BIN)/riscv64-unknown-elf-
else
  RISCV_PREFIX ?= riscv64-unknown-elf-
endif

RTL := $(ROOT_DIR)/components/*.v $(ROOT_DIR)/main/*.v $(ROOT_DIR)/main/soc/*.v \
       $(ROOT_DIR)/uncore/*.sv $(ROOT_DIR)/debugger/*.v $(ROOT_DIR)/debugger/*.sv
TB  := $(CURDIR)/tb/spi_partner_model.sv $(CURDIR)/tb/tb_spi_boot_e2e.sv
INCDIRS := main main/soc components uncore debugger

TEST_ELF := $(BUILD)/boot_e2e.elf
EXT_ELF  := $(SW_DIR)/build/bootrom_ext.elf
MODE0    := $(BUILD)/mode0.bin
MODE1    := $(BUILD)/mode1.bin
BAD_KINDS := gap below above iram_end dram_end oversize
BAD       := $(foreach k,$(BAD_KINDS),$(BUILD)/bad_$(k).bin)

ifeq ($(SIM),icarus)
  RUN_SIM = $(VVP) -n tb.vvp
else
  RUN_SIM = $(VSIM) -c -voptargs="+acc" -do "run -all; quit -f" work.tb_spi_boot_e2e
endif

S4_TARGETS := $(foreach k,$(BAD_KINDS),s4_$(k))
SCENARIOS := s1 s2 s3 $(S4_TARGETS) s5 s6 s7 s8a s8b

.PHONY: all test_all help check_rom streams compile clean FORCE s4 $(SCENARIOS)

all: test_all

help:
	@echo "Subsystem 09: SPI boot flow, end to end (SIM=questa|icarus)"
	@echo "  s1   mode-0 boot ([test])"
	@echo "  s2   mode-1 boot ([second-stage ROM][test])"
	@echo "  s3   partner not armed -> error 0xE1, debugger readout"
	@echo "  s4   bounds check -> error 0xE2 (s4_gap s4_below s4_above s4_iram_end s4_dram_end s4_oversize)"
	@echo "  s5   boot, then debugger core reset -> restarts in RAM, no boot ROM"
	@echo "  s6   boot, then SYSCTRL soft reset -> boots again through the ROM"
	@echo "  s7   rule R4: SoC reset (after / during a load) does not rewind the partner"
	@echo "  s8a  mode-1 boot with the Pi 4 timed partner (poll 200 ns, latency 300 ns)"
	@echo "  s8b  mode-0 boot with a 5x slower Pi 4 (poll 1000 ns, latency 500 ns)"
	@echo "  test_all, streams, clean"

$(BUILD):
	@mkdir -p $(BUILD)

# The table in rom_ahb.sv must be the SPI loader (its first word is "lui sp,0x80018").
check_rom:
	@grep -q "32'h8001_8137" $(ROOT_DIR)/uncore/rom_ahb.sv || \
	 { echo "ERROR: source/uncore/rom_ahb.sv does not hold the SPI boot loader."; \
	   echo "       Run: make -C software rom   (then re-run this suite)"; exit 1; }

$(TEST_ELF): src/boot_e2e.S $(SW_DIR)/link.ld | $(BUILD)
	$(RISCV_PREFIX)gcc -march=rv32i -mabi=ilp32 -nostdlib -nostartfiles -T $(SW_DIR)/link.ld $< -o $@

$(EXT_ELF): FORCE
	@$(MAKE) --no-print-directory -C $(SW_DIR) build/bootrom_ext.elf RISCV_PREFIX=$(RISCV_PREFIX) >/dev/null

$(MODE0): $(TEST_ELF) $(SW_DIR)/make_image.py
	$(PYTHON) $(SW_DIR)/make_image.py --mode 0 --test $(TEST_ELF) -o $@ --dump

$(MODE1): $(TEST_ELF) $(EXT_ELF) $(SW_DIR)/make_image.py
	$(PYTHON) $(SW_DIR)/make_image.py --mode 1 --test $(TEST_ELF) --ext $(EXT_ELF) -o $@ --dump

$(BUILD)/bad_%.bin: $(MODE0) scripts/make_bad_stream.py
	$(PYTHON) scripts/make_bad_stream.py $(MODE0) $@ $*

streams: check_rom $(MODE0) $(MODE1) $(BAD)

compile: streams
	@echo "--- Compiling SoC RTL + SPI boot testbench ($(SIM)) ---"
ifeq ($(SIM),icarus)
	@cd $(BUILD) && $(IVERILOG) -g2012 -o tb.vvp -s tb_spi_boot_e2e $(addprefix -I$(ROOT_DIR)/,$(INCDIRS)) \
	   $(RTL) $(TB) > compile.log 2>&1 || { grep -iE "error" compile.log; exit 1; }
else
	@cd $(BUILD) && rm -rf work && $(VLIB) work >/dev/null && \
	 $(VLOG) -sv -timescale 1ns/1ps -work work $(addprefix +incdir+$(ROOT_DIR)/,$(INCDIRS)) \
	   $(RTL) $(TB) > compile.log 2>&1 || { grep -E "\*\* Error" compile.log; exit 1; }
endif

# $(1) = target, $(2) = description, $(3) = plusargs
define run_scenario
	@echo ""
	@echo "=== [09_SPI_BOOT] $(1): $(2) ==="
	@cd $(BUILD) && $(RUN_SIM) $(3) > $(1).log 2>&1; \
	 grep -E "\[PASS\]|\[FAIL\]|SCENARIO|outcome=|  -- |S7b:" $(1).log | sed 's/^# //'
	@grep -q "RESULT: PASS" $(BUILD)/$(1).log
endef

s1: compile
	$(call run_scenario,s1,mode-0 boot,+SCEN=s1 +STREAM=$(MODE0))
s2: compile
	$(call run_scenario,s2,mode-1 boot,+SCEN=s2 +STREAM=$(MODE1))
s3: compile
	$(call run_scenario,s3,partner not armed -> E1,+SCEN=s3)
s4: $(S4_TARGETS)
$(S4_TARGETS): s4_%: compile
	$(call run_scenario,s4_$*,bounds check ($*) -> E2,+SCEN=s4 +STREAM=$(BUILD)/bad_$*.bin)
s5: compile
	$(call run_scenario,s5,debugger core reset bypasses the boot ROM,+SCEN=s5 +STREAM=$(MODE0))
s6: compile
	$(call run_scenario,s6,SYSCTRL soft reset boots again,+SCEN=s6 +STREAM=$(MODE0))
s7: compile
	$(call run_scenario,s7,SoC reset does not rewind the partner (R4),+SCEN=s7 +STREAM=$(MODE0))
s8a: compile
	$(call run_scenario,s8a,mode-1 boot with the Pi 4 timed partner,+SCEN=s2 +STREAM=$(MODE1) +PI_TIMED +POLL=200 +LAT=300)
s8b: compile
	$(call run_scenario,s8b,mode-0 boot with a 5x slower Pi 4,+SCEN=s1 +STREAM=$(MODE0) +PI_TIMED +POLL=1000 +LAT=500)

test_all: $(SCENARIOS)
	@echo ""
	@echo "================================================================"
	@echo " ALL SPI BOOT END-TO-END SCENARIOS PASSED ($(SCENARIOS))"
	@echo "================================================================"

clean:
	@rm -rf $(BUILD)
	@echo "Cleaned 09_spi_boot_e2e build artifacts."
