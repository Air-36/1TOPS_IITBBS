#include "soc_regs.h"

void trap_dispatcher(uint32_t cause, uint32_t epc) {
    fail_test(0xEE);
}

static inline void spi_tx_byte(uint8_t b) {
    while (SPI_TXDATA & 0x80000000); // Wait while TX FIFO is full
    SPI_TXDATA = (uint32_t)b;
}

static inline uint8_t spi_rx_byte(void) {
    uint32_t val;
    do {
        val = SPI_RXDATA;
    } while (val & 0x80000000); // Wait while RX FIFO is empty
    return (uint8_t)(val & 0xFF);
}

static inline uint8_t spi_xfer_byte(uint8_t b) {
    spi_tx_byte(b);
    return spi_rx_byte();
}

int main(void) {
    // 1. Configure SPI Controller
    SPI_SCKDIV = 2;
    SPI_CSMODE = SPI_CSMODE_HOLD; // Assert CS0 and keep it asserted

    // 2. Transmit READ command (0x03) and 24-bit address (0x000000)
    // Discard the dummy bytes received during command/address transmission
    (void)spi_xfer_byte(0x03);
    (void)spi_xfer_byte(0x00);
    (void)spi_xfer_byte(0x00);
    (void)spi_xfer_byte(0x00);

    // 3. Clock in 4 data bytes from SPI Flash
    uint8_t received[4];
    for (int i = 0; i < 4; i++) {
        received[i] = spi_xfer_byte(0x00);
    }

    // 4. Deassert CS
    SPI_CSMODE = SPI_CSMODE_AUTO;

    // 5. Verify data bytes received from spi_flash_model: 0x13, 0x05, 0xA0, 0x02
    if (received[0] != 0x13 || received[1] != 0x05 ||
        received[2] != 0xA0 || received[3] != 0x02) {
        fail_test(((uint32_t)received[0] << 24) | ((uint32_t)received[1] << 16) | ((uint32_t)received[2] << 8) | (uint32_t)received[3]);
    }

    pass_test();
    return 0;
}
