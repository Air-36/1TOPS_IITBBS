#include "soc_regs.h"

static volatile uint32_t sw_irq_count = 0;

void trap_dispatcher(uint32_t cause, uint32_t epc) {
    if (cause == CAUSE_MSW_INT) {
        sw_irq_count++;
        // Clear software interrupt bit in CLINT
        CLINT_MSIP = 0;
    } else {
        fail_test(0xE0 | (cause & 0xF));
    }
}

int main(void) {
    sw_irq_count = 0;

    // Enable Software Interrupt in mie (MSIE) and global interrupts in mstatus (MIE)
    set_csr_mie(MIE_MSIE);
    set_csr_mstatus(MSTATUS_MIE);

    // Trigger Software Interrupt by asserting CLINT MSIP
    CLINT_MSIP = 1;

    // Wait for ISR execution
    uint32_t timeout = 50000;
    while (sw_irq_count == 0) {
        if (--timeout == 0) {
            fail_test(1);
        }
    }

    clear_csr_mstatus(MSTATUS_MIE);
    clear_csr_mie(MIE_MSIE);

    if (sw_irq_count != 1) {
        fail_test(2);
    }

    pass_test();
    return 0;
}

