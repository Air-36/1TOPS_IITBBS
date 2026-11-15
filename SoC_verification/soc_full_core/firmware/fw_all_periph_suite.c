#include "soc_regs.h"

static volatile uint32_t timer_irq_count = 0;
static volatile uint32_t plic_irq_count = 0;

void trap_dispatcher(uint32_t cause, uint32_t epc) {
    if (cause == CAUSE_MTIMER_INT) {
        timer_irq_count++;
        CLINT_MTIMECMPH = 0xFFFFFFFF;
        CLINT_MTIMECMP  = 0xFFFFFFFF; // Clear timer interrupt
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

static inline void spi_tx_byte(uint8_t b) {
    while (SPI_TXDATA & 0x80000000);
    SPI_TXDATA = (uint32_t)b;
}

static inline uint8_t spi_rx_byte(void) {
    uint32_t val;
    do {
        val = SPI_RXDATA;
    } while (val & 0x80000000);
    return (uint8_t)(val & 0xFF);
}

static inline uint8_t spi_xfer_byte(uint8_t b) {
    spi_tx_byte(b);
    return spi_rx_byte();
}

int main(void) {
    // -------------------------------------------------------------------------
    // Phase 1: Hardware Multiplier Accelerator Test
    // -------------------------------------------------------------------------
    MULT_OPA = 123;
    MULT_OPB = 456;
    if (MULT_RESULT != (123 * 456)) {
        fail_test(1);
    }

    // -------------------------------------------------------------------------
    // Phase 2: GPIO Input / Output
    // -------------------------------------------------------------------------
    GPIO_OUTPUT_EN = 0x0000000F;
    GPIO_INPUT_EN  = 0x000000F0;
    GPIO_OUTPUT_VAL = 0x0000000A;

    // -------------------------------------------------------------------------
    // Phase 3: UART 16550 String Transmission
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
    (void)spi_xfer_byte(0x03);
    (void)spi_xfer_byte(0x00);
    (void)spi_xfer_byte(0x00);
    (void)spi_xfer_byte(0x00);

    uint8_t spi_b[4];
    for (int i = 0; i < 4; i++) {
        spi_b[i] = spi_xfer_byte(0x00);
    }
    SPI_CSMODE = SPI_CSMODE_AUTO;

    if (spi_b[0] != 0x13 || spi_b[1] != 0x05) {
        fail_test(4);
    }

    // -------------------------------------------------------------------------
    // Phase 5: Interrupts (CLINT Timer + PLIC GPIO)
    // -------------------------------------------------------------------------
    // Setup PLIC & GPIO edge detection
    GPIO_INPUT_EN  = 0xFFFFFFFF;
    GPIO_RISE_IE   = (1U << 3);
    GPIO_RISE_IP   = 0xFFFFFFFF;
    PLIC_PRIO_GPIO = 3;
    PLIC_ENABLE    = (1U << 2);
    PLIC_THRESHOLD = 0;

    // Setup Timer
    uint32_t t_now = CLINT_MTIME;
    CLINT_MTIMECMPH = 0;
    CLINT_MTIMECMP  = t_now + 300;

    // Enable interrupts
    set_csr_mie(MIE_MTIE | MIE_MEIE);
    set_csr_mstatus(MSTATUS_MIE);

    // Notify testbench that PLIC & Timer are armed
    REG32(MAILBOX_STATUS_ADDR) = STATUS_READY_PLIC;

    // Await both interrupts
    uint32_t timeout = 100000;
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
