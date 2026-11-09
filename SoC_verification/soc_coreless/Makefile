# =============================================================================
# Makefile: Full Coreless 1TOPS SoC UVM Verification
# Simulator: QuestaSim (primary) & VCS (alternative)
# =============================================================================

TOP_DIR := ..
RTL_DIR := $(TOP_DIR)/rtl
VIP_DIR := $(TOP_DIR)/vip

VLIB ?= vlib
VLOG ?= vlog
VSIM ?= vsim

TEST ?= soc_all_suite_test

VLOG_ARGS = -sv -timescale 1ns/1ps \
	+incdir+$(VIP_DIR)/ahb_lite_vip \
	+incdir+$(VIP_DIR)/apb_vip \
	+incdir+$(VIP_DIR)/gpio_vip \
	+incdir+$(VIP_DIR)/irq_vip \
	+incdir+$(RTL_DIR)/components \
	+incdir+$(RTL_DIR)/main \
	+incdir+$(RTL_DIR)/main/soc \
	+incdir+$(RTL_DIR)/uncore \
	+incdir+$(RTL_DIR)/debugger \
	+incdir+dut \
	+incdir+env \
	+incdir+tests \
	+incdir+tb

VSIM_ARGS = -c -voptargs="+acc" +UVM_TESTNAME=$(TEST) +UVM_VERBOSITY=UVM_LOW

all: run

compile:
	rm -rf work transcript vsim.wlf
	$(VLIB) work
	$(VLOG) $(VLOG_ARGS) \
		$(VIP_DIR)/ahb_lite_vip/ahb_lite_if.sv \
		$(VIP_DIR)/ahb_lite_vip/ahb_lite_pkg.sv \
		$(VIP_DIR)/apb_vip/apb_if.sv \
		$(VIP_DIR)/apb_vip/apb_pkg.sv \
		$(VIP_DIR)/gpio_vip/gpio_if.sv \
		$(VIP_DIR)/gpio_vip/gpio_pkg.sv \
		$(VIP_DIR)/irq_vip/irq_if.sv \
		$(VIP_DIR)/irq_vip/irq_pkg.sv \
		$(RTL_DIR)/components/*.v \
		$(RTL_DIR)/main/*.v \
		$(RTL_DIR)/main/soc/*.v \
		$(RTL_DIR)/uncore/*.sv \
		$(RTL_DIR)/debugger/*.v \
		$(RTL_DIR)/debugger/*.sv \
		tb/ahb_protocol_checker.sv \
		tb/spi_flash_model.sv \
		dut/riscv_soc_ahb_coreless.sv \
		env/soc_coreless_env_pkg.sv \
		tests/soc_test_pkg.sv \
		tb/tb_soc_coreless_top.sv

run: compile
	$(VSIM) $(VSIM_ARGS) -do "run -all; quit -f" work.tb_soc_coreless_top

test_reset: compile
	$(VSIM) -c -voptargs="+acc" +UVM_TESTNAME=soc_reset_test +UVM_VERBOSITY=UVM_LOW -do "run -all; quit -f" work.tb_soc_coreless_top

test_single_rw: compile
	$(VSIM) -c -voptargs="+acc" +UVM_TESTNAME=soc_ahb_single_rw_test +UVM_VERBOSITY=UVM_LOW -do "run -all; quit -f" work.tb_soc_coreless_top

test_addr_decode: compile
	$(VSIM) -c -voptargs="+acc" +UVM_TESTNAME=soc_ahb_address_decode_test +UVM_VERBOSITY=UVM_LOW -do "run -all; quit -f" work.tb_soc_coreless_top

test_gpio_vip: compile
	$(VSIM) -c -voptargs="+acc" +UVM_TESTNAME=soc_gpio_vip_test +UVM_VERBOSITY=UVM_LOW -do "run -all; quit -f" work.tb_soc_coreless_top

test_clint_irq: compile
	$(VSIM) -c -voptargs="+acc" +UVM_TESTNAME=soc_clint_irq_test +UVM_VERBOSITY=UVM_LOW -do "run -all; quit -f" work.tb_soc_coreless_top

test_plic_irq: compile
	$(VSIM) -c -voptargs="+acc" +UVM_TESTNAME=soc_plic_irq_test +UVM_VERBOSITY=UVM_LOW -do "run -all; quit -f" work.tb_soc_coreless_top

test_remap: compile
	$(VSIM) -c -voptargs="+acc" +UVM_TESTNAME=soc_sysctrl_remap_test +UVM_VERBOSITY=UVM_LOW -do "run -all; quit -f" work.tb_soc_coreless_top

test_stress: compile
	$(VSIM) -c -voptargs="+acc" +UVM_TESTNAME=soc_concurrency_stress_test +UVM_VERBOSITY=UVM_LOW -do "run -all; quit -f" work.tb_soc_coreless_top

test_all_suite: compile
	$(VSIM) -c -voptargs="+acc" +UVM_TESTNAME=soc_all_suite_test +UVM_VERBOSITY=UVM_LOW -do "run -all; quit -f" work.tb_soc_coreless_top

clean:
	rm -rf work transcript vsim.wlf *.log

