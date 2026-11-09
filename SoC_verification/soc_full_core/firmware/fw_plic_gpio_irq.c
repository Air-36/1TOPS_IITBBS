#include "soc_regs.h"

static volatile uint32_t plic_irq_count = 0;
static volatile uint32_t claimed_id = 0;

void trap_dispatcher(uint32_t cause, uint32_t epc) {
    if (cause == CAUSE_MEXT_INT) {
        // 1. Claim interrupt from PLIC
        uint32_t id = PLIC_CLAIM;
        claimed_id = id;

        if (id == 2) { // Source 2 = GPIO
            plic_irq_count++;
            // 2. Clear edge interrupt in GPIO controller (write-1-to-clear)
            GPIO_RISE_IP = (1U << 3);
            // 3. Complete interrupt in PLIC
            PLIC_CLAIM = id;
        } else {
            // Unexpected interrupt source
            PLIC_CLAIM = id;
            fail_test(0xD0 | (id & 0xF));
        }
    } else {
        fail_test(0xE0 | (cause & 0xF));
    }
}

int main(void) {
    plic_irq_count = 0;
    claimed_id = 0;

    // 1. Configure GPIO controller to trigger interrupt on rising edge of bit 3
    GPIO_INPUT_EN = 0xFFFFFFFF;
    GPIO_RISE_IE  = (1U << 3);
    GPIO_RISE_IP  = 0xFFFFFFFF; // Clear any stale pending

    // 2. Configure PLIC
    PLIC_PRIO_GPIO = 3;         // Priority for source 2 = 3
    PLIC_ENABLE    = (1U << 2); // Enable source 2
    PLIC_THRESHOLD = 0;         // Threshold = 0

    // 3. Enable External Interrupt in Core
    set_csr_mie(MIE_MEIE);
    set_csr_mstatus(MSTATUS_MIE);

    // 4. Signal Testbench VIP that CPU is ready to receive GPIO edge
    REG32(MAILBOX_STATUS_ADDR) = STATUS_READY_PLIC;

    // 5. Wait for PLIC interrupt to be serviced
    uint32_t timeout = 100000;
    while (plic_irq_count == 0) {
        if (--timeout == 0) {
            fail_test(1); // Timeout waiting for PLIC interrupt
        }
    }

    clear_csr_mstatus(MSTATUS_MIE);
    clear_csr_mie(MIE_MEIE);

    if (plic_irq_count != 1 || claimed_id != 2) {
        fail_test(2);
    }

    pass_test();
    return 0;
}

