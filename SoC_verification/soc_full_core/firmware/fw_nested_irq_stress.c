#include "soc_regs.h"

static volatile uint32_t timer_irq_ticks = 0;
static volatile uint32_t sw_irq_ticks = 0;

void trap_dispatcher(uint32_t cause, uint32_t epc) {
    if (cause == CAUSE_MTIMER_INT) {
        timer_irq_ticks++;
        // Reschedule next timer interrupt 150 cycles later
        uint32_t cur = CLINT_MTIME;
        CLINT_MTIMECMPH = 0;
        CLINT_MTIMECMP  = cur + 150;
    } else if (cause == CAUSE_MSW_INT) {
        sw_irq_ticks++;
        CLINT_MSIP = 0; // Clear software IRQ
    } else {
        fail_test(0xE0 | (cause & 0xF));
    }
}

int main(void) {
    timer_irq_ticks = 0;
    sw_irq_ticks = 0;

    // Schedule initial timer interrupt in 100 cycles
    uint32_t cur = CLINT_MTIME;
    CLINT_MTIMECMPH = 0;
    CLINT_MTIMECMP  = cur + 100;

    // Enable both Timer and Software interrupts
    set_csr_mie(MIE_MTIE | MIE_MSIE);
    set_csr_mstatus(MSTATUS_MIE);

    // Stress Workload 1: Dense memory load/store operations
    volatile uint32_t *scratch_buf = (volatile uint32_t *)(DRAM_BASE + 0x2000);
    for (int i = 0; i < 64; i++) {
        scratch_buf[i] = i * 17 + 3;
    }

    // Trigger a software interrupt mid-workload
    CLINT_MSIP = 1;

    // Stress Workload 2: Intensive branch and ALU loop under periodic timer interrupts
    uint32_t accumulator = 0;
    for (int i = 0; i < 200; i++) {
        accumulator += scratch_buf[i % 64];
        if (accumulator & 1) {
            accumulator = (accumulator * 3) + 1;
        } else {
            accumulator = accumulator >> 1;
        }
    }

    // Disable interrupts to verify state
    clear_csr_mstatus(MSTATUS_MIE);
    clear_csr_mie(MIE_MTIE | MIE_MSIE);

    // Verify interrupts occurred during execution
    if (timer_irq_ticks == 0) {
        fail_test(1); // No timer IRQ fired during workload
    }
    if (sw_irq_ticks == 0) {
        fail_test(2); // No SW IRQ handled
    }

    // Verify buffer data integrity after multiple interrupts
    for (int i = 0; i < 64; i++) {
        if (scratch_buf[i] != (uint32_t)(i * 17 + 3)) {
            fail_test(0x30 + (i & 0xF));
        }
    }

    pass_test();
    return 0;
}

