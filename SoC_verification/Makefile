# =============================================================================
# Master Makefile: 1TOPS RISC-V SoC UVM Verification Framework
# Location: SoC_verification/Makefile
# Simulator: QuestaSim (mentor/questasim/2023.4_5)
# =============================================================================

SHELL := /bin/bash

.PHONY: all help regression unit_all soc_all clean \
        unit_gpio unit_clint unit_plic unit_sysctrl unit_multiplier unit_uart unit_spi \
        soc_reset soc_single_rw soc_addr_decode soc_gpio_vip soc_clint_irq soc_plic_irq soc_remap soc_stress

help:
	@echo "============================================================================="
	@echo "             1TOPS RISC-V Coreless SoC UVM Verification Framework            "
	@echo "============================================================================="
	@echo "Available Targets:"
	@echo "  make regression         : Run complete regression (all unit + full SoC tests)"
	@echo "  make unit_all           : Run all 7 peripheral IP unit testbenches"
	@echo "  make soc_all            : Run complete coreless SoC master test suite"
	@echo ""
	@echo "Standalone IP Unit Tests (Uncore Peripherals):"
	@echo "  make unit_gpio          : GPIO APB + GPIO VIP + APB VIP unit testbench"
	@echo "  make unit_clint         : CLINT APB + IRQ VIP (Timer & SW IRQs)"
	@echo "  make unit_plic          : PLIC APB + IRQ VIP (Priorities, Claim/Complete)"
	@echo "  make unit_sysctrl       : SysCtrl APB (Reset, Vectors, Remap, SYS_ID)"
	@echo "  make unit_multiplier    : Hardware Multiplier AHB Slave unit test"
	@echo "  make unit_uart          : 16550 UART APB unit testbench"
	@echo "  make unit_spi           : SPI Controller APB unit testbench"
	@echo ""
	@echo "Coreless SoC Verification (Without CPU/Debugger Masters):"
	@echo "  make soc_reset          : SoC cold reset & default telemetry test"
	@echo "  make soc_single_rw      : Single AHB Read/Write transactions across all domains"
	@echo "  make soc_addr_decode    : Comprehensive address decoding across all 11 SoC slaves"
	@echo "  make soc_gpio_vip       : End-to-end GPIO VIP loopback & edge interrupt"
	@echo "  make soc_clint_irq      : End-to-end CLINT MTimerInt & MSwInt via AHB"
	@echo "  make soc_plic_irq       : End-to-end Peripheral -> PLIC -> MExtInt routing & claim"
	@echo "  make soc_remap          : SysCtrl Boot ROM to IRAM address remapping test"
	@echo "  make soc_stress         : Concurrent stress traffic (IRAM, DRAM, Multiplier, GPIO)"
	@echo ""
	@echo "Cleanup:"
	@echo "  make clean              : Clean simulation artifacts across all directories"
	@echo "============================================================================="

all: regression

regression: unit_all soc_all
	@echo ""
	@echo "============================================================================="
	@echo " [PASS] ALL UNIT TESTS AND CORELESS SOC SUITES COMPLETED SUCCESSFULLY!      "
	@echo "============================================================================="

# -----------------------------------------------------------------------------
# Unit Test Targets (IP Level)
# -----------------------------------------------------------------------------
unit_all: unit_gpio unit_clint unit_plic unit_sysctrl unit_multiplier unit_uart unit_spi
	@echo "============================================================================="
	@echo " [PASS] ALL 7 IP UNIT TESTS COMPLETED SUCCESSFULLY!                         "
	@echo "============================================================================="

unit_gpio:
	@echo "[RUNNING] Unit Test: GPIO Peripheral + GPIO VIP..."
	$(MAKE) -C unit_tests/gpio run

unit_clint:
	@echo "[RUNNING] Unit Test: CLINT Peripheral + IRQ VIP..."
	$(MAKE) -C unit_tests/clint run

unit_plic:
	@echo "[RUNNING] Unit Test: PLIC Peripheral + IRQ VIP..."
	$(MAKE) -C unit_tests/plic run

unit_sysctrl:
	@echo "[RUNNING] Unit Test: System Controller Peripheral..."
	$(MAKE) -C unit_tests/sysctrl run

unit_multiplier:
	@echo "[RUNNING] Unit Test: Multiplier AHB Slave..."
	$(MAKE) -C unit_tests/multiplier run

unit_uart:
	@echo "[RUNNING] Unit Test: 16550 UART Peripheral..."
	$(MAKE) -C unit_tests/uart run

unit_spi:
	@echo "[RUNNING] Unit Test: SPI Controller Peripheral..."
	$(MAKE) -C unit_tests/spi run

# -----------------------------------------------------------------------------
# Coreless SoC Targets (Subsystem Level)
# -----------------------------------------------------------------------------
soc_all:
	@echo "[RUNNING] Coreless SoC Master Suite (All Integration Phases)..."
	$(MAKE) -C soc_coreless test_all_suite

soc_reset:
	$(MAKE) -C soc_coreless test_reset

soc_single_rw:
	$(MAKE) -C soc_coreless test_single_rw

soc_addr_decode:
	$(MAKE) -C soc_coreless test_addr_decode

soc_gpio_vip:
	$(MAKE) -C soc_coreless test_gpio_vip

soc_clint_irq:
	$(MAKE) -C soc_coreless test_clint_irq

soc_plic_irq:
	$(MAKE) -C soc_coreless test_plic_irq

soc_remap:
	$(MAKE) -C soc_coreless test_remap

soc_stress:
	$(MAKE) -C soc_coreless test_stress

# -----------------------------------------------------------------------------
# Cleanup
# -----------------------------------------------------------------------------
clean:
	@echo "Cleaning up all verification directories..."
	$(MAKE) -C unit_tests/gpio clean
	$(MAKE) -C unit_tests/clint clean
	$(MAKE) -C unit_tests/plic clean
	$(MAKE) -C unit_tests/sysctrl clean
	$(MAKE) -C unit_tests/multiplier clean
	$(MAKE) -C unit_tests/uart clean
	$(MAKE) -C unit_tests/spi clean
	$(MAKE) -C soc_coreless clean
	@echo "Clean completed."

