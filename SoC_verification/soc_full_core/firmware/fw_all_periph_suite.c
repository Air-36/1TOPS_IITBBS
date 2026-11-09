#include "soc_regs.h"

static volatile uint32_t timer_irq_count = 0;
static volatile uint32_t plic_irq_count = 0;

void trap_dispatcher(uint32_t cause, uint32_t epc) {
    if (cause == CAUSE_MTIMER_INT) {
        timer_irq_count++;
        CLINT_MTIMECMP = 0xFFFFFFFF; // Clear timer interrupt
    } else if (cause == CAUSE_MEXT_INT) {
        uint32_t id = PLIC_CLAIM;
        if (id == 2) {
            plic_irq_count++;
            GPIO_RISE_IP = (1U << 3);
            PLIC_CLAIM = id;
        } else {
            PLIC_CLAIM = id;
            fail_test(0xD0 | (id & 0xF));
        }
    } else {
        fail_test(0xE0 | (cause & 0xF));
    }
}

static void delay_cycles(uint32_t n) {
    for (volatile uint32_t i = 0; i < n; i++) {
        __asm__ volatile ("nop");
    }
}

int main(void) {
    // -------------------------------------------------------------------------
    // Phase 1: Memory & Accelerator
    // -------------------------------------------------------------------------
    volatile uint32_t *dram = (volatile uint32_t *)(DRAM_BASE + 0x3000);
    for (int i = 0; i < 32; i++) {
        dram[i] = 0xAA550000 + i;
    }
    for (int i = 0; i < 32; i++) {
        if (dram[i] != (0xAA550000 + i)) {
            fail_test(1);
        }
    }

    MULT_OPA = 45;
    MULT_OPB = 67;
    if (MULT_RESULT != (45 * 67)) {
        fail_test(2);
    }

    // -------------------------------------------------------------------------
    // Phase 2: GPIO & VIP Handshake
    // -------------------------------------------------------------------------
    GPIO_OUTPUT_EN = 0x0000FFFF;
    GPIO_INPUT_EN  = 0xFFFF0000;
    GPIO_OUTPUT_VAL = 0x0000BEEF;

    // -------------------------------------------------------------------------
    // Phase 3: UART Transmission
    // -------------------------------------------------------------------------
    UART_LCR = 0x80;
    UART_DLL = 0x01;
    UART_DLM = 0x00;
    UART_LCR = 0x03;
    UART_FCR = 0x07;

    const char *msg = "1TOPS_SOC_FULL_SUITE_PASS\n";
    while (*msg) {
        while (!(UART_LSR & UART_LSR_THRE)) {}
        UART_THR = (uint32_t)(*msg++);
    }

    // -------------------------------------------------------------------------
    // Phase 4: SPI Flash Read
    // -------------------------------------------------------------------------
    SPI_SCKDIV = 2;
    SPI_CSMODE = SPI_CSMODE_HOLD;
    SPI_TXDATA = 0x03;
    SPI_TXDATA = 0x00;
    SPI_TXDATA = 0x00;
    SPI_TXDATA = 0x00;
    delay_cycles(120);

    volatile uint32_t d;
    d = SPI_RXDATA; d = SPI_RXDATA; d = SPI_RXDATA; d = SPI_RXDATA;
    (void)d;

    uint8_t spi_b[4];
    for (int i = 0; i < 4; i++) {
        SPI_TXDATA = 0x00;
        delay_cycles(30);
        spi_b[i] = (uint8_t)(SPI_RXDATA & 0xFF);
    }
    SPI_CSMODE = SPI_CSMODE_AUTO;

    if (spi_b[0] != 0x13 || spi_b[1] != 0x05) {
        fail_test(4);
    }

    // -------------------------------------------------------------------------
    // Phase 5: Interrupts (CLINT Timer + PLIC GPIO)
    // -------------------------------------------------------------------------
    // Setup PLIC
    GPIO_RISE_IE   = (1U << 3);
    GPIO_RISE_IP   = 0xFFFFFFFF;
    PLIC_PRIO_GPIO = 3;
    PLIC_ENABLE    = (1U << 2);
    PLIC_THRESHOLD = 0;

    // Setup Timer
    uint32_t t_now = CLINT_MTIME;
    CLINT_MTIMECMP = t_now + 250;

    // Enable interrupts
    set_csr_mie(MIE_MTIE | MIE_MEIE);
    set_csr_mstatus(MSTATUS_MIE);

    // Notify testbench that PLIC & Timer are armed
    REG32(MAILBOX_STATUS_ADDR) = STATUS_READY_PLIC;

    // Await both interrupts
    uint32_t timeout = 80000;
    while (timer_irq_count == 0 || plic_irq_count == 0) {
        if (--timeout == 0) {
            fail_test(5);
        }
    }

    clear_csr_mstatus(MSTATUS_MIE);
    clear_csr_mie(MIE_MTIE | MIE_MEIE);

    pass_test();
    return 0;
}

