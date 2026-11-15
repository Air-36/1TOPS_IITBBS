#!/bin/bash
# =============================================================================
# Script: run_regression.sh
# Purpose: Master Regression Runner for 1TOPS SoC UVM Verification
# Environment: QuestaSim (mentor/questasim/2023.4_5)
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Color formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}=============================================================================${NC}"
echo -e "${CYAN}             1TOPS RISC-V Full SoC UVM Verification Regression               ${NC}"
echo -e "${CYAN}=============================================================================${NC}"

# Check for QuestaSim
if ! command -v vsim &> /dev/null; then
    echo -e "${YELLOW}[NOTE] Loading QuestaSim module mentor/questasim/2023.4_5...${NC}"
    module load mentor/questasim/2023.4_5 2>/dev/null || true
fi

TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
START_TIME=$(date +%s)

declare -a TEST_NAMES=(
    "Level 1 [01/27] Unit: GPIO APB + GPIO VIP"
    "Level 1 [02/27] Unit: CLINT APB + IRQ VIP (Timer & SW IRQ)"
    "Level 1 [03/27] Unit: PLIC APB + IRQ VIP (Routing & Claim)"
    "Level 1 [04/27] Unit: SysCtrl APB (Reset & Remap)"
    "Level 1 [05/27] Unit: Multiplier AHB Slave"
    "Level 1 [06/27] Unit: 16550 UART APB"
    "Level 1 [07/27] Unit: SPI Controller APB"
    "Level 2 [08/27] SoC Coreless: Reset & Telemetry Test"
    "Level 2 [09/27] SoC Coreless: Single AHB Read/Write Test"
    "Level 2 [10/27] SoC Coreless: Exhaustive Address Decoding"
    "Level 2 [11/27] SoC Coreless: GPIO VIP Loopback & Edge IRQ"
    "Level 2 [12/27] SoC Coreless: CLINT Timer & SW IRQs"
    "Level 2 [13/27] SoC Coreless: PLIC Routing & Claim via AHB"
    "Level 2 [14/27] SoC Coreless: SysCtrl ROM-to-RAM Remap"
    "Level 2 [15/27] SoC Coreless: Concurrency & Stress Traffic"
    "Level 2 [16/27] SoC Coreless: Master Integration Suite"
    "Level 3 [17/27] Full SoC: Boot & Bringup Memory March"
    "Level 3 [18/27] Full SoC: Core GPIO + VIP 2-Way Handshake"
    "Level 3 [19/27] Full SoC: 16550 UART Stream to UART VIP"
    "Level 3 [20/27] Full SoC: SPI Controller & Flash Behavioral"
    "Level 3 [21/27] Full SoC: CLINT Timer IRQ to Core & ISR"
    "Level 3 [22/27] Full SoC: CLINT Software IRQ to Core & ISR"
    "Level 3 [23/27] Full SoC: GPIO -> PLIC -> Core MExtInt"
    "Level 3 [24/27] Full SoC: Nested IRQs & Memory/Branch Stress"
    "Level 3 [25/27] Full SoC: Boot Mode 0 (Internal ROM Diag)"
    "Level 3 [26/27] Full SoC: Boot Mode 1 (SPI Flash -> IMEM)"
    "Level 3 [27/27] Full SoC: Master All-Peripheral Suite"
)

declare -a TEST_COMMANDS=(
    "make -C unit_tests/gpio run"
    "make -C unit_tests/clint run"
    "make -C unit_tests/plic run"
    "make -C unit_tests/sysctrl run"
    "make -C unit_tests/multiplier run"
    "make -C unit_tests/uart run"
    "make -C unit_tests/spi run"
    "make -C soc_coreless test_reset"
    "make -C soc_coreless test_single_rw"
    "make -C soc_coreless test_addr_decode"
    "make -C soc_coreless test_gpio_vip"
    "make -C soc_coreless test_clint_irq"
    "make -C soc_coreless test_plic_irq"
    "make -C soc_coreless test_remap"
    "make -C soc_coreless test_stress"
    "make -C soc_coreless test_all_suite"
    "make -C soc_full_core test_bringup"
    "make -C soc_full_core test_gpio"
    "make -C soc_full_core test_uart"
    "make -C soc_full_core test_spi"
    "make -C soc_full_core test_clint_timer"
    "make -C soc_full_core test_clint_sw"
    "make -C soc_full_core test_plic"
    "make -C soc_full_core test_stress"
    "make -C soc_full_core test_boot_mode0"
    "make -C soc_full_core test_boot_mode1"
    "make -C soc_full_core test_suite"
)

mkdir -p regression_logs

for i in "${!TEST_NAMES[@]}"; do
    NAME="${TEST_NAMES[$i]}"
    CMD="${TEST_COMMANDS[$i]}"
    LOG="regression_logs/test_$((i+1)).log"
    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    printf "[%2d/%2d] Running: %-62s " "$TOTAL_TESTS" "${#TEST_NAMES[@]}" "$NAME"
    
    if bash -c "$CMD" > "$LOG" 2>&1; then
        # Check for UVM errors in log
        ERR_COUNT=$(grep -c "UVM_ERROR : *[1-9]" "$LOG" || true)
        FAT_COUNT=$(grep -c "UVM_FATAL : *[1-9]" "$LOG" || true)
        if [ "$ERR_COUNT" -eq 0 ] && [ "$FAT_COUNT" -eq 0 ]; then
            echo -e "${GREEN}[PASSED]${NC}"
            PASSED_TESTS=$((PASSED_TESTS + 1))
        else
            echo -e "${RED}[FAILED - UVM Errors Detected]${NC} (Log: $LOG)"
            FAILED_TESTS=$((FAILED_TESTS + 1))
        fi
    else
        echo -e "${RED}[FAILED - Exit Code Non-Zero]${NC} (Log: $LOG)"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
done

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

echo ""
echo -e "${CYAN}=============================================================================${NC}"
echo -e "${CYAN}                            REGRESSION SUMMARY                               ${NC}"
echo -e "${CYAN}=============================================================================${NC}"
echo -e "Total Tests Run : ${TOTAL_TESTS}"
echo -e "Passed Tests    : ${GREEN}${PASSED_TESTS}${NC}"
echo -e "Failed Tests    : $( [ $FAILED_TESTS -eq 0 ] && echo -e "${GREEN}0${NC}" || echo -e "${RED}${FAILED_TESTS}${NC}" )"
echo -e "Elapsed Time    : ${ELAPSED} seconds"
echo -e "${CYAN}=============================================================================${NC}"

if [ "$FAILED_TESTS" -eq 0 ]; then
    echo -e "${GREEN}>>> 100% SUCCESS: ALL 1TOPS SoC UVM TESTBENCHES PASSED! <<<${NC}"
    exit 0
else
    echo -e "${RED}>>> REGRESSION FAILED with ${FAILED_TESTS} failures. Inspect logs in regression_logs/ <<<${NC}"
    exit 1
fi

