#include <stdio.h>
#include <string.h>
#include "pico/stdlib.h"
#include "pico/stdio_usb.h"
#include "hardware/spi.h"
#include "hardware/dma.h"
#include "hardware/resets.h"

#define PIN_RX   16   // MOSI in  (from Basys 3 JC2)
#define PIN_CS   17   // CSn in   (from Basys 3 JC1)
#define PIN_SCK  18   // SCK in   (from Basys 3 JC4)
#define PIN_TX   19   // MISO out (to Basys 3 JC3)
#define PIN_LED  25   // Onboard Pico LED

#define MAXLEN   (96 * 1024)

static uint8_t buf[MAXLEN];
static uint8_t rx_sink;
static int tx_ch = -1;
static int rx_ch = -1;
static uint32_t armed_len = 0;

static void spi_slave_arm(uint32_t len) {
    // 1. Claim DMA channels once
    if (tx_ch < 0) {
        tx_ch = dma_claim_unused_channel(true);
        rx_ch = dma_claim_unused_channel(true);
    } else {
        // Stop any in-flight DMA transfers before resetting SPI
        dma_channel_abort(tx_ch);
        dma_channel_abort(rx_ch);
    }

    // 2. Hardware-reset SPI0 so TX/RX FIFOs and shift register are completely empty (Rule 4)
    reset_block(RESETS_RESET_SPI0_BITS);
    unreset_block_wait(RESETS_RESET_SPI0_BITS);

    // 3. Configure SPI0 as Mode 3 Slave (CPOL=1, CPHA=1, 8-bit, MSB first)
    spi_init(spi0, 1000 * 1000); // Baud rate is ignored in slave mode, required by API
    spi_set_slave(spi0, true);
    spi_set_format(spi0, 8, SPI_CPOL_1, SPI_CPHA_1, SPI_MSB_FIRST);

    gpio_set_function(PIN_RX,  GPIO_FUNC_SPI);
    gpio_set_function(PIN_CS,  GPIO_FUNC_SPI);
    gpio_set_function(PIN_SCK, GPIO_FUNC_SPI);
    gpio_set_function(PIN_TX,  GPIO_FUNC_SPI);

    // 4. Configure TX DMA: buf[] -> SPI0 TX FIFO paced by SPI0 TX DREQ
    dma_channel_config c_tx = dma_channel_get_default_config(tx_ch);
    channel_config_set_transfer_data_size(&c_tx, DMA_SIZE_8);
    channel_config_set_read_increment(&c_tx, true);
    channel_config_set_write_increment(&c_tx, false);
    channel_config_set_dreq(&c_tx, spi_get_dreq(spi0, true));
    dma_channel_configure(
        tx_ch,
        &c_tx,
        &spi_get_hw(spi0)->dr, // Write to SPI0 data register
        buf,                   // Read from stream buffer
        len,                   // Total bytes in stream
        true                   // Start immediately (pre-fills the 8-byte TX FIFO)
    );

    // 5. Configure RX DMA: SPI0 RX FIFO -> rx_sink paced by SPI0 RX DREQ
    dma_channel_config c_rx = dma_channel_get_default_config(rx_ch);
    channel_config_set_transfer_data_size(&c_rx, DMA_SIZE_8);
    channel_config_set_read_increment(&c_rx, false);
    channel_config_set_write_increment(&c_rx, false);
    channel_config_set_dreq(&c_rx, spi_get_dreq(spi0, false));
    dma_channel_configure(
        rx_ch,
        &c_rx,
        &rx_sink,              // Discard incoming dummy 0x00 bytes
        &spi_get_hw(spi0)->dr, // Read from SPI0 data register
        len,                   // Expect len bytes clocked by master
        true                   // Start immediately
    );

    armed_len = len;
    gpio_put(PIN_LED, 1);      // LED ON = Armed and waiting for SoC clocks
}

static bool read_exact(uint8_t *p, uint32_t n, uint32_t timeout_us) {
    for (uint32_t i = 0; i < n; i++) {
        int c = getchar_timeout_us(timeout_us);
        if (c == PICO_ERROR_TIMEOUT) {
            return false;
        }
        p[i] = (uint8_t)c;
    }
    return true;
}

static void write_str(const char *s) {
    fwrite(s, 1, strlen(s), stdout);
    stdio_flush();
}

int main(void) {
    stdio_init_all();
    // CRITICAL: Disable CRLF translation so 0x0A/0x0D bytes are never altered
    stdio_set_translate_crlf(&stdio_usb, false);

    gpio_init(PIN_LED);
    gpio_set_dir(PIN_LED, GPIO_OUT);
    gpio_put(PIN_LED, 0);

    uint8_t win[4] = {0, 0, 0, 0};

    for (;;) {
        // Poll for 1 byte with a short timeout so we can update LED state when transfer finishes
        int c = getchar_timeout_us(50000);
        if (c == PICO_ERROR_TIMEOUT) {
            // Turn off LED once the SoC has clocked out the entire armed stream
            if (armed_len > 0 && rx_ch >= 0 && dma_channel_hw_addr(rx_ch)->transfer_count == 0) {
                gpio_put(PIN_LED, 0);
            }
            continue;
        }

        // Sliding 4-byte window to resync cleanly on any garbage bytes
        win[0] = win[1];
        win[1] = win[2];
        win[2] = win[3];
        win[3] = (uint8_t)c;

        if (memcmp(win, "PICO", 4) == 0) {
            memset(win, 0, sizeof(win));

            uint8_t len_bytes[4];
            if (!read_exact(len_bytes, 4, 1000000)) {
                write_str("E3"); // Timeout reading length
                continue;
            }

            uint32_t len = (uint32_t)len_bytes[0]
                         | ((uint32_t)len_bytes[1] << 8)
                         | ((uint32_t)len_bytes[2] << 16)
                         | ((uint32_t)len_bytes[3] << 24);

            if (len == 0 || len > MAXLEN) {
                write_str("E2"); // Invalid/oversized stream length
                continue;
            }

            if (!read_exact(buf, len, 2000000)) {
                write_str("E3"); // Timeout reading payload
                continue;
            }

            spi_slave_arm(len);
            write_str("OK");
        } else if (memcmp(win, "STAT", 4) == 0) {
            memset(win, 0, sizeof(win));
            uint32_t rem = (rx_ch >= 0) ? dma_channel_hw_addr(rx_ch)->transfer_count : 0;
            uint32_t sent = armed_len - rem;
            char msg[64];
            snprintf(msg, sizeof(msg), "ARMED=%lu SENT=%lu REM=%lu\n",
                     (unsigned long)armed_len, (unsigned long)sent, (unsigned long)rem);
            write_str(msg);
        }
    }
}