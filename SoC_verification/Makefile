# =============================================================================
# Master Makefile: 1TOPS RISC-V SoC UVM Verification Framework
# Location: SoC_verification/Makefile
# Simulator: QuestaSim (mentor/questasim/2023.4_5)
# =============================================================================

SHELL := /bin/bash

.PHONY: all help regression unit_all soc_all full_all clean \
        unit_gpio unit_clint unit_plic unit_sysctrl unit_multiplier unit_uart unit_spi \
        soc_reset soc_single_rw soc_addr_decode soc_gpio_vip soc_clint_irq soc_plic_irq soc_remap soc_stress \
        full_bringup full_gpio full_uart full_spi full_clint_timer full_clint_sw full_plic full_stress full_boot_mode0 full_boot_mode1 full_suite

help:
	@echo "============================================================================="
	@echo "             1TOPS RISC-V SoC UVM Verification Framework                     "
	@echo "============================================================================="
	@echo "Available Master Targets:"
	@echo "  make regression         : Run complete 3-level regression (27 tests)"
	@echo "  make unit_all           : Run all 7 peripheral IP unit testbenches"
	@echo "  make soc_all            : Run complete coreless SoC master test suite"
	@echo "  make full_all           : Run all 11 full SoC with RISC-V CPU core tests"
	@echo ""
	@echo "Level 1: Standalone IP Unit Tests (Uncore Peripherals):"
	@echo "  make unit_gpio          : GPIO APB + GPIO VIP + APB VIP unit testbench"
	@echo "  make unit_clint         : CLINT APB + IRQ VIP (Timer & SW IRQs)"
	@echo "  make unit_plic          : PLIC APB + IRQ VIP (Priorities, Claim/Complete)"
	@echo "  make unit_sysctrl       : SysCtrl APB (Reset, Vectors, Remap, SYS_ID)"
	@echo "  make unit_multiplier    : Hardware Multiplier AHB Slave unit test"
	@echo "  make unit_uart          : 16550 UART APB unit testbench"
	@echo "  make unit_spi           : SPI Controller APB unit testbench"
	@echo ""
	@echo "Level 2: Coreless SoC Verification (Without CPU/Debugger Masters):"
	@echo "  make soc_reset          : SoC cold reset & default telemetry test"
	@echo "  make soc_single_rw      : Single AHB Read/Write transactions across all domains"
	@echo "  make soc_addr_decode    : Comprehensive address decoding across all 11 SoC slaves"
	@echo "  make soc_gpio_vip       : End-to-end GPIO VIP loopback & edge interrupt"
	@echo "  make soc_clint_irq      : End-to-end CLINT MTimerInt & MSwInt via AHB"
	@echo "  make soc_plic_irq       : End-to-end Peripheral -> PLIC -> MExtInt routing & claim"
	@echo "  make soc_remap          : SysCtrl Boot ROM to IRAM address remapping test"
	@echo "  make soc_stress         : Concurrent stress traffic (IRAM, DRAM, Multiplier, GPIO)"
	@echo ""
	@echo "Level 3: Full SoC with RISC-V CPU Core Verification (Firmware + VIPs):"
	@echo "  make full_bringup       : Memory march, walking ones, scratchpad, HW multiplier"
	@echo "  make full_gpio          : Core GPIO output driving + VIP input polling"
	@echo "  make full_uart          : 16550 UART string transmission to UART VIP Monitor"
	@echo "  make full_spi           : SPI Flash behavioral model command 0x03 byte read"
	@echo "  make full_clint_timer   : CLINT mtimecmp Timer Interrupt delivered to Core ISR"
	@echo "  make full_clint_sw      : CLINT msip Software Interrupt delivered to Core ISR"
	@echo "  make full_plic          : GPIO rising edge -> PLIC -> Core MExtInt -> Claim/Complete"
	@echo "  make full_stress        : Robustness under nested timer & SW IRQs with memory/branch stress"
	@echo "  make full_boot_mode0    : Boot Mode 0: Internal Boot ROM diagnostics execution"
	@echo "  make full_boot_mode1    : Boot Mode 1: Boot ROM SPI Flash loader -> IMEM jump & exec"
	@echo "  make full_suite         : Comprehensive Master Suite (All peripherals + IRQs + Core)"
	@echo ""
	@echo "Cleanup:"
	@echo "  make clean              : Clean simulation artifacts across all directories"
	@echo "============================================================================="

all: regression

regression: unit_all soc_all full_all
	@echo ""
	@echo "============================================================================="
	@echo " [PASS] ALL UNIT, CORELESS SOC, AND FULL SOC WITH CORE TESTS PASSED!        "
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
# Full SoC with RISC-V Core Targets (Level 3)
# -----------------------------------------------------------------------------
full_all: full_bringup full_gpio full_uart full_spi full_clint_timer full_clint_sw full_plic full_stress full_boot_mode0 full_boot_mode1 full_suite
	@echo "============================================================================="
	@echo " [PASS] ALL 11 FULL SOC WITH CORE TESTS COMPLETED SUCCESSFULLY!             "
	@echo "============================================================================="

full_bringup:
	@echo "[RUNNING] Full SoC: Boot & Bringup Memory March..."
	$(MAKE) -C soc_full_core test_bringup

full_gpio:
	@echo "[RUNNING] Full SoC: Core GPIO + VIP 2-Way Handshake..."
	$(MAKE) -C soc_full_core test_gpio

full_uart:
	@echo "[RUNNING] Full SoC: 16550 UART Stream to VIP..."
	$(MAKE) -C soc_full_core test_uart

full_spi:
	@echo "[RUNNING] Full SoC: SPI Controller & SPI Flash Model..."
	$(MAKE) -C soc_full_core test_spi

full_clint_timer:
	@echo "[RUNNING] Full SoC: CLINT Timer Interrupt to Core..."
	$(MAKE) -C soc_full_core test_clint_timer

full_clint_sw:
	@echo "[RUNNING] Full SoC: CLINT Software Interrupt to Core..."
	$(MAKE) -C soc_full_core test_clint_sw

full_plic:
	@echo "[RUNNING] Full SoC: GPIO -> PLIC -> Core MExtInt Routing..."
	$(MAKE) -C soc_full_core test_plic

full_stress:
	@echo "[RUNNING] Full SoC: Robustness Under Load & Nested IRQs..."
	$(MAKE) -C soc_full_core test_stress

full_boot_mode0:
	@echo "[RUNNING] Full SoC: Boot Mode 0 (Internal ROM Diagnostics)..."
	$(MAKE) -C soc_full_core test_boot_mode0

full_boot_mode1:
	@echo "[RUNNING] Full SoC: Boot Mode 1 (SPI Flash Loader -> IMEM)..."
	$(MAKE) -C soc_full_core test_boot_mode1

full_suite:
	@echo "[RUNNING] Full SoC: Comprehensive Master Peripheral Suite..."
	$(MAKE) -C soc_full_core test_suite

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
	$(MAKE) -C soc_full_core clean
	@echo "Clean completed."

