# ==============================================================================
# Makefile: Full 1TOPS RISC-V SoC Verification (Core + Memory + VIPs)
# ==============================================================================

RTL_DIR       := ../rtl
VIP_DIR       := ../vip
TB_DIR        := tb
ENV_DIR       := env
TEST_DIR      := tests
FW_DIR        := firmware

VSIM_CMD      := module load mentor/questasim/2023.4_5 && vsim
VLOG_CMD      := module load mentor/questasim/2023.4_5 && vlog

VLOG_OPTS     := -sv -timescale "1ns/1ps" +acc=all -suppress 12110,2244,7033,2892,13314
VSIM_OPTS     := -c -voptargs="+acc" -suppress 12110,2244,7033,2892,13314 -do "run -all; quit -f"

INCLUDES      := +incdir+$(VIP_DIR)/gpio_vip \
                 +incdir+$(VIP_DIR)/irq_vip \
                 +incdir+$(VIP_DIR)/uart_vip \
                 +incdir+$(ENV_DIR) \
                 +incdir+$(TEST_DIR) \
                 +incdir+$(TB_DIR) \
                 +incdir+$(RTL_DIR)/uncore \
                 +incdir+$(RTL_DIR)/components \
                 +incdir+$(RTL_DIR)/main \
                 +incdir+$(RTL_DIR)/debugger

# Source files
RTL_SRCS      := $(RTL_DIR)/components/*.v \
                 $(RTL_DIR)/uncore/*.sv \
                 $(RTL_DIR)/debugger/*.v \
                 $(RTL_DIR)/debugger/*.sv \
                 $(RTL_DIR)/main/pipelined/riscv_pipelined.v \
                 $(RTL_DIR)/main/riscv_cpu.v \
                 $(RTL_DIR)/main/soc/riscv_soc_ahb.v

VIP_SRCS      := $(VIP_DIR)/gpio_vip/gpio_if.sv \
                 $(VIP_DIR)/gpio_vip/gpio_pkg.sv \
                 $(VIP_DIR)/irq_vip/irq_if.sv \
                 $(VIP_DIR)/irq_vip/irq_pkg.sv \
                 $(VIP_DIR)/uart_vip/uart_if.sv \
                 $(VIP_DIR)/uart_vip/uart_pkg.sv

TB_SRCS       := $(TB_DIR)/spi_flash_model.sv \
                 $(TB_DIR)/cpu_exec_monitor.sv \
                 $(TB_DIR)/ahb_protocol_checker.sv \
                 $(TB_DIR)/apb_protocol_checker.sv \
                 $(ENV_DIR)/soc_full_env_pkg.sv \
                 $(TEST_DIR)/soc_full_tests_pkg.sv \
                 $(TB_DIR)/tb_soc_full_top.sv

.PHONY: all firmware compile clean all_tests

all: firmware compile

firmware:
	$(MAKE) -C $(FW_DIR) all

compile:
	$(VSIM_CMD) -c -do "vlib work; quit -f"
	$(VLOG_CMD) $(VLOG_OPTS) $(INCLUDES) $(RTL_SRCS) $(VIP_SRCS) $(TB_SRCS)

# --- Test Targets ---
test_bringup: compile
	$(VSIM_CMD) $(VSIM_OPTS) work.tb_soc_full_top \
		+INSTR_MEM=$(FW_DIR)/fw_boot_bringup_instr.mem \
		+DATA_MEM=$(FW_DIR)/fw_boot_bringup_data.mem \
		+UVM_TESTNAME=soc_full_bringup_test

test_gpio: compile
	$(VSIM_CMD) $(VSIM_OPTS) work.tb_soc_full_top \
		+INSTR_MEM=$(FW_DIR)/fw_gpio_vip_instr.mem \
		+DATA_MEM=$(FW_DIR)/fw_gpio_vip_data.mem \
		+UVM_TESTNAME=soc_full_gpio_test

test_uart: compile
	$(VSIM_CMD) $(VSIM_OPTS) work.tb_soc_full_top \
		+INSTR_MEM=$(FW_DIR)/fw_uart_stream_instr.mem \
		+DATA_MEM=$(FW_DIR)/fw_uart_stream_data.mem \
		+UVM_TESTNAME=soc_full_uart_test

test_spi: compile
	$(VSIM_CMD) $(VSIM_OPTS) work.tb_soc_full_top \
		+INSTR_MEM=$(FW_DIR)/fw_spi_loopback_instr.mem \
		+DATA_MEM=$(FW_DIR)/fw_spi_loopback_data.mem \
		+UVM_TESTNAME=soc_full_spi_test

test_clint_timer: compile
	$(VSIM_CMD) $(VSIM_OPTS) work.tb_soc_full_top \
		+INSTR_MEM=$(FW_DIR)/fw_clint_timer_irq_instr.mem \
		+DATA_MEM=$(FW_DIR)/fw_clint_timer_irq_data.mem \
		+UVM_TESTNAME=soc_full_clint_test

test_clint_sw: compile
	$(VSIM_CMD) $(VSIM_OPTS) work.tb_soc_full_top \
		+INSTR_MEM=$(FW_DIR)/fw_clint_sw_irq_instr.mem \
		+DATA_MEM=$(FW_DIR)/fw_clint_sw_irq_data.mem \
		+UVM_TESTNAME=soc_full_clint_test

test_plic: compile
	$(VSIM_CMD) $(VSIM_OPTS) work.tb_soc_full_top \
		+INSTR_MEM=$(FW_DIR)/fw_plic_gpio_irq_instr.mem \
		+DATA_MEM=$(FW_DIR)/fw_plic_gpio_irq_data.mem \
		+UVM_TESTNAME=soc_full_plic_test

test_stress: compile
	$(VSIM_CMD) $(VSIM_OPTS) work.tb_soc_full_top \
		+INSTR_MEM=$(FW_DIR)/fw_nested_irq_stress_instr.mem \
		+DATA_MEM=$(FW_DIR)/fw_nested_irq_stress_data.mem \
		+UVM_TESTNAME=soc_full_stress_test

test_suite: compile
	$(VSIM_CMD) $(VSIM_OPTS) work.tb_soc_full_top \
		+INSTR_MEM=$(FW_DIR)/fw_all_periph_suite_instr.mem \
		+DATA_MEM=$(FW_DIR)/fw_all_periph_suite_data.mem \
		+UVM_TESTNAME=soc_full_suite_test

test_boot_mode0: compile
	$(VSIM_CMD) $(VSIM_OPTS) -gUSE_BOOTROM=1 work.tb_soc_full_top \
		+UVM_TESTNAME=soc_full_boot_test

test_boot_mode1: compile
	$(VSIM_CMD) $(VSIM_OPTS) -gUSE_BOOTROM=1 work.tb_soc_full_top \
		+BOOT_MODE_1 \
		+UVM_TESTNAME=soc_full_boot_test

all_tests: test_bringup test_gpio test_uart test_spi test_clint_timer test_clint_sw test_plic test_stress test_boot_mode0 test_boot_mode1 test_suite

clean:
	rm -rf work transcript *.wlf
	$(MAKE) -C $(FW_DIR) clean

