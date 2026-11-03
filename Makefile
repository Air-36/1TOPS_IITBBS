# =============================================================================
# 1TOPS RISC-V SoC Master Makefile
# =============================================================================

.PHONY: all help test_all test_subsystems clean clean-all software \
        test_01_core_modules test_02_pipeline_hazard test_03_cpu_core_arch \
        test_04_bus_fabric test_05_peripherals test_06_debugger test_07_benchmarks

all: help

help:
	@echo "=================================================================="
	@echo " 1TOPS RISC-V Pipelined SoC Master Makefile"
	@echo "=================================================================="
	@echo " Available Targets:"
	@echo "   make software                - Build software & bare-metal test binaries"
	@echo "   make test_all                - Run all 7 complete subsystem verification suites"
	@echo "   make test_01_core_modules    - Subsystem 1: Core Datapath & ALU"
	@echo "   make test_02_pipeline_hazard - Subsystem 2: Microarchitectural Stress & SVA"
	@echo "   make test_03_cpu_core_arch   - Subsystem 3: CPU Architectural Compliance vs Spike"
	@echo "   make test_04_bus_fabric      - Subsystem 4: AMBA AHB/APB Bus Fabric (CRV)"
	@echo "   make test_05_peripherals     - Subsystem 5: Peripherals & Multiplier Accel"
	@echo "   make test_06_debugger        - Subsystem 6: Hardware Debugger & ADP Protocols"
	@echo "   make test_07_benchmarks      - Subsystem 7: Bare-Metal C SoC Benchmarks"
	@echo "   make clean                   - Clean all build and simulation artifacts"
	@echo "   make clean-all               - Deep clean including editor backups & caches"
	@echo "=================================================================="

# 1. Bare-metal Software Compilation
software:
	@if [ -d software ]; then \
		$(MAKE) -C software clean && $(MAKE) -C software; \
	fi

# 2. Complete 7-Subsystem Verification Suites
test_all:
	@$(MAKE) -C source/final_tests test_all

test_subsystems: test_all

test_01_core_modules:
	@$(MAKE) -C source/final_tests test_01_core_modules

test_02_pipeline_hazard:
	@$(MAKE) -C source/final_tests test_02_pipeline_hazard

test_03_cpu_core_arch:
	@$(MAKE) -C source/final_tests test_03_cpu_core_arch

test_04_bus_fabric:
	@$(MAKE) -C source/final_tests test_04_bus_fabric

test_05_peripherals:
	@$(MAKE) -C source/final_tests test_05_peripherals

test_06_debugger:
	@$(MAKE) -C source/final_tests test_06_debugger

test_07_benchmarks:
	@$(MAKE) -C source/final_tests test_07_benchmarks

# 3. Clean
clean:
	@if [ -d software ]; then $(MAKE) -C software clean; fi
	@if [ -d source/final_tests ]; then $(MAKE) -C source/final_tests clean; fi
	@if [ -d source/testbench ]; then $(MAKE) -C source/testbench clean; fi
	@for d in source/standard_core_tests/*/; do \
		if [ -f "$${d}Makefile" ]; then $(MAKE) -C "$$d" clean; fi \
	done
	@rm -rf schematics/vivado*.log schematics/vivado*.jou schematics/vivado*.str
	@rm -rf schematics/*.backup.log schematics/*.backup.jou schematics/.Xil
	@rm -rf fpga/build/vivado_project fpga/build/*.log fpga/build/*.jou fpga/build/.Xil fpga/build/xsim.dir
	@rm -rf work output_files simulation transcript* vsim.wlf *.wlf

clean-all: clean
	find . -type f -name '*~' -delete
	find . -type f -name '*.bak' -delete
	find . -type d -name '__pycache__' -exec rm -rf {} +
	find . -type f -name '.DS_Store' -delete
