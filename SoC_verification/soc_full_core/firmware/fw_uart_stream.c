#include "soc_regs.h"

void trap_dispatcher(uint32_t cause, uint32_t epc) {
    fail_test(0xEE);
}

static void uart_init(void) {
    // Enable DLAB to configure baud divisor
    UART_LCR = 0x80;
    UART_DLL = 0x01; // Divisor = 1 for fastest simulation cycle
    UART_DLM = 0x00;
    // 8 data bits, 1 stop bit, no parity (DLAB cleared)
    UART_LCR = 0x03;
    // Enable and clear FIFO
    UART_FCR = 0x07;
}

static void uart_putc(char c) {
    // Wait until Transmit Holding Register is empty
    while (!(UART_LSR & UART_LSR_THRE)) {
        // spin
    }
    UART_THR = (uint32_t)c;
}

static void uart_puts(const char *s) {
    while (*s) {
        uart_putc(*s++);
    }
}

int main(void) {
    uart_init();

    // Transmit verification header
    uart_puts("HELLO_1TOPS_RISCV_SOC_UART_OK\n");

    // Wait until transmitter is completely empty
    while (!(UART_LSR & UART_LSR_TEMT)) {
        // spin
    }

    pass_test();
    return 0;
}

