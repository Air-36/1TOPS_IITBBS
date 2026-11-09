#include "soc_regs.h"

static volatile uint32_t timer_irq_count = 0;
static volatile uint32_t last_epc = 0;

void trap_dispatcher(uint32_t cause, uint32_t epc) {
    if (cause == CAUSE_MTIMER_INT) {
        timer_irq_count++;
        last_epc = epc;
        // Clear timer interrupt condition by setting mtimecmp far in the future
        CLINT_MTIMECMP  = 0xFFFFFFFF;
        CLINT_MTIMECMPH = 0xFFFFFFFF;
    } else {
        fail_test(0xE0 | (cause & 0xF));
    }
}

int main(void) {
    timer_irq_count = 0;

    // Read current timer value
    uint32_t cur_time = CLINT_MTIME;

    // Schedule timer interrupt 300 cycles in the future
    CLINT_MTIMECMPH = 0;
    CLINT_MTIMECMP  = cur_time + 300;

    // Enable Timer Interrupt in mie (MTIE) and global interrupts in mstatus (MIE)
    set_csr_mie(MIE_MTIE);
    set_csr_mstatus(MSTATUS_MIE);

    // Wait for timer interrupt to fire
    uint32_t timeout = 50000;
    while (timer_irq_count == 0) {
        if (--timeout == 0) {
            fail_test(1); // Timeout waiting for timer ISR
        }
    }

    // Disable timer interrupts
    clear_csr_mstatus(MSTATUS_MIE);
    clear_csr_mie(MIE_MTIE);

    if (timer_irq_count != 1) {
        fail_test(2);
    }

    pass_test();
    return 0;
}

