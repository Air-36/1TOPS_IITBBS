#include "soc_regs.h"

// Dummy trap dispatcher for tests that don't expect interrupts
void trap_dispatcher(uint32_t cause, uint32_t epc) {
    fail_test(0xEE); // Unexpected trap
}

int main(void) {
    // 1. Basic CPU Arithmetic Sanity Check
    volatile uint32_t a = 1234;
    volatile uint32_t b = 5678;
    volatile uint32_t sum = a + b;
    if (sum != 6912) {
        fail_test(1);
    }

    // 2. SysCtrl Scratchpad Register R/W Test
    SYSCTRL_SCRATCHPAD = 0xA55A1234;
    if (SYSCTRL_SCRATCHPAD != 0xA55A1234) {
        fail_test(2);
    }
    SYSCTRL_SCRATCHPAD = 0x5AA54321;
    if (SYSCTRL_SCRATCHPAD != 0x5AA54321) {
        fail_test(3);
    }

    // 3. Multiplier Hardware Accelerator Test (0x3000_0000)
    MULT_OPA = 123;
    MULT_OPB = 456;
    if (MULT_RESULT != (123 * 456)) {
        fail_test(4);
    }

    MULT_OPA = 10000;
    MULT_OPB = 2500;
    if (MULT_RESULT != 25000000) {
        fail_test(5);
    }

    // 4. Memory Walking Ones & March Test on Data RAM
    volatile uint32_t *dram_test_ptr = (volatile uint32_t *)(DRAM_BASE + 0x1000);
    for (int bit = 0; bit < 32; bit++) {
        uint32_t pattern = (1U << bit);
        dram_test_ptr[bit] = pattern;
    }
    for (int bit = 0; bit < 32; bit++) {
        uint32_t expected = (1U << bit);
        if (dram_test_ptr[bit] != expected) {
            fail_test(0x10 + bit);
        }
    }

    // 5. Memory March Test (Incremental pattern write and verify)
    for (int i = 0; i < 128; i++) {
        dram_test_ptr[i] = 0x55AA0000 + i;
    }
    for (int i = 0; i < 128; i++) {
        if (dram_test_ptr[i] != (0x55AA0000 + i)) {
            fail_test(0x30 + (i & 0xF));
        }
    }

    // All tests passed
    pass_test();
    return 0;
}

