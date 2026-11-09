#include "soc_regs.h"

void trap_dispatcher(uint32_t cause, uint32_t epc) {
    fail_test(0xEE);
}

int main(void) {
    // Enable lower 16 bits as outputs, upper 16 bits as inputs
    GPIO_OUTPUT_EN = 0x0000FFFF;
    GPIO_INPUT_EN  = 0xFFFF0000;

    // Step 1: Drive pattern A5A5 on lower 16 bits
    GPIO_OUTPUT_VAL = 0x0000A5A5;

    // Step 2: Poll GPIO_INPUT_VAL until upper 16 bits match expected VIP stimulus 0x56780000
    uint32_t timeout = 50000;
    while ((GPIO_INPUT_VAL & 0xFFFF0000) != 0x56780000) {
        if (--timeout == 0) {
            fail_test(1); // Timeout waiting for VIP input stimulus
        }
    }

    // Step 3: Acknowledge by driving pattern 5A5A on lower 16 bits
    GPIO_OUTPUT_VAL = 0x00005A5A;

    // Step 4: Wait for VIP second stimulus 0x12340000
    timeout = 50000;
    while ((GPIO_INPUT_VAL & 0xFFFF0000) != 0x12340000) {
        if (--timeout == 0) {
            fail_test(2);
        }
    }

    // Step 5: Final output pattern 0x0000CAFE
    GPIO_OUTPUT_VAL = 0x0000CAFE;

    pass_test();
    return 0;
}

