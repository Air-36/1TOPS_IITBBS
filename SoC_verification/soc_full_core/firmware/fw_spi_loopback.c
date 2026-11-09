#include "soc_regs.h"

void trap_dispatcher(uint32_t cause, uint32_t epc) {
    fail_test(0xEE);
}

static void delay_cycles(uint32_t n) {
    for (volatile uint32_t i = 0; i < n; i++) {
        __asm__ volatile ("nop");
    }
}

int main(void) {
    // 1. Configure SPI Controller
    SPI_SCKDIV = 2;
    SPI_CSMODE = SPI_CSMODE_HOLD; // Assert CS0

    // 2. Transmit READ command (0x03) and 24-bit address (0x000000)
    SPI_TXDATA = 0x03;
    SPI_TXDATA = 0x00;
    SPI_TXDATA = 0x00;
    SPI_TXDATA = 0x00;

    // Wait ~300 cycles for 4 bytes to transfer
    delay_cycles(150);

    // Drain the 4 bytes shifted in during command/address
    volatile uint32_t dummy;
    dummy = SPI_RXDATA;
    dummy = SPI_RXDATA;
    dummy = SPI_RXDATA;
    dummy = SPI_RXDATA;
    (void)dummy;

    // 3. Shift in 4 data bytes from SPI Flash
    uint8_t received[4];
    for (int i = 0; i < 4; i++) {
        SPI_TXDATA = 0x00; // Generate 8 clock cycles
        delay_cycles(40);
        received[i] = (uint8_t)(SPI_RXDATA & 0xFF);
    }

    // 4. Deassert CS
    SPI_CSMODE = SPI_CSMODE_AUTO;

    // 5. Verify data bytes received from spi_flash_model: 0x13, 0x05, 0xA0, 0x02
    if (received[0] != 0x13 || received[1] != 0x05 ||
        received[2] != 0xA0 || received[3] != 0x02) {
        fail_test((received[0] << 24) | (received[1] << 16) | (received[2] << 8) | received[3]);
    }

    pass_test();
    return 0;
}

