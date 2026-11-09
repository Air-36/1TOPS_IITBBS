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
echo -e "${CYAN}             1TOPS RISC-V Coreless SoC UVM Verification Regression           ${NC}"
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
    "Unit: GPIO Peripheral (APB + GPIO VIP)"
    "Unit: CLINT Peripheral (Timer + SW IRQs)"
    "Unit: PLIC Peripheral (IRQ Routing + Claim)"
    "Unit: SysCtrl Peripheral (Reset + Remap)"
    "Unit: Multiplier AHB Slave"
    "Unit: 16550 UART APB"
    "Unit: SPI Controller APB"
    "SoC Coreless: Reset & Telemetry Test"
    "SoC Coreless: Single AHB Read/Write Test"
    "SoC Coreless: Exhaustive Address Decoding"
    "SoC Coreless: GPIO VIP Loopback & Edge IRQ"
    "SoC Coreless: CLINT Timer & SW IRQs"
    "SoC Coreless: PLIC Routing & Claim via AHB"
    "SoC Coreless: SysCtrl ROM-to-RAM Remap"
    "SoC Coreless: Concurrency & Stress Traffic"
    "SoC Coreless: Master Suite (All Integration Phases)"
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
)

mkdir -p regression_logs

for i in "${!TEST_NAMES[@]}"; do
    NAME="${TEST_NAMES[$i]}"
    CMD="${TEST_COMMANDS[$i]}"
    LOG="regression_logs/test_$((i+1)).log"
    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    printf "[%2d/%2d] Running: %-52s " "$TOTAL_TESTS" "${#TEST_NAMES[@]}" "$NAME"
    
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

