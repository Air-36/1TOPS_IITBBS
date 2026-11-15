// =============================================================================
// hw.c - Raspberry Pi 4 (BCM2711) GPIO, PL011 UART0, system timer, ACT LED.
// =============================================================================
#include "hw.h"
#include "protocol.h"

void gpio_fsel(uint32_t pin, uint32_t fn)
{
    uintptr_t reg = GPFSEL(pin / 10u);
    uint32_t shift = (pin % 10u) * 3u;
    uint32_t v = mmio_read(reg);
    v &= ~(7u << shift);
    v |= (fn & 7u) << shift;
    mmio_write(reg, v);
}

// BCM2711 pull control: GPIO_PUP_PDN_CNTRL_REGn, 2 bits per pin
// (00 none, 01 up, 10 down). No clocked sequence needed (unlike BCM2835).
void gpio_pull(uint32_t pin, uint32_t pull)
{
    uintptr_t reg = GPIO_PUP_PDN(pin / 16u);
    uint32_t shift = (pin % 16u) * 2u;
    uint32_t v = mmio_read(reg);
    v &= ~(3u << shift);
    v |= (pull & 3u) << shift;
    mmio_write(reg, v);
}

void led_set(int on)
{
    mmio_write(on ? GPSET1 : GPCLR1, 1u << (PIN_ACT_LED - 32u));
}

uint32_t timer_us(void)
{
    return mmio_read(SYSTMR_CLO);
}

static void uart_init(void)
{
    // PL011 programming sequence: disable, wait for the end of any transmission,
    // flush the FIFOs (FEN = 0), program, re-enable.
    mmio_write(UART_CR, 0);
    uint32_t t0 = timer_us();                  // bounded wait: never hang at boot
    while ((mmio_read(UART_FR) & UART_FR_BUSY) && (uint32_t)(timer_us() - t0) < 10000u) {
    }
    mmio_write(UART_LCRH, 0);

    // Detach UART0 from the Bluetooth pins (the firmware routes it to GPIO 30-33,
    // ALT3) so that RXD comes only from GPIO 15; then route it to the header.
    for (uint32_t pin = 30u; pin <= 33u; pin++)
        gpio_fsel(pin, GPIO_FSEL_INPUT);
    gpio_fsel(14u, GPIO_FSEL_ALT0);       // TXD0
    gpio_fsel(15u, GPIO_FSEL_ALT0);       // RXD0
    gpio_pull(14u, GPIO_PULL_NONE);
    gpio_pull(15u, GPIO_PULL_UP);         // idle high if the adapter is unplugged

    // Divider = UART_CLK / (16 * baud) as 16.6 fixed point, rounded.
    const uint32_t div64 = (4u * UART_CLK_HZ + UART_BAUD / 2u) / UART_BAUD;
    mmio_write(UART_ICR, 0x7FFu);         // clear all interrupt flags
    mmio_write(UART_IBRD, div64 >> 6);    // 115200 @ 48 MHz: 26
    mmio_write(UART_FBRD, div64 & 63u);   //                  3   (error -0.02 %)
    mmio_write(UART_LCRH, UART_LCRH_WLEN8 | UART_LCRH_FEN);   // 8N1, FIFOs on
    mmio_write(UART_IMSC, 0);             // no interrupts (polled)
    mmio_write(UART_CR, UART_CR_UARTEN | UART_CR_TXE | UART_CR_RXE);
}

void hw_init(void)
{
    // MISO: set the output latch HIGH before making it an output (no low glitch).
    mmio_write(GPSET0, MISO_MASK);
    gpio_fsel(PIN_MISO, GPIO_FSEL_OUTPUT);
    gpio_pull(PIN_MISO, GPIO_PULL_NONE);

    gpio_fsel(PIN_SCLK, GPIO_FSEL_INPUT);
    gpio_fsel(PIN_CS,   GPIO_FSEL_INPUT);
    gpio_fsel(PIN_MOSI, GPIO_FSEL_INPUT);
    gpio_pull(PIN_SCLK, GPIO_PULL_UP);    // mode 3 idle level
    gpio_pull(PIN_CS,   GPIO_PULL_UP);    // unplugged/unconfigured SoC = CS inactive
    gpio_pull(PIN_MOSI, GPIO_PULL_DOWN);

    mmio_write(GPCLR1, 1u << (PIN_ACT_LED - 32u));
    gpio_fsel(PIN_ACT_LED, GPIO_FSEL_OUTPUT);

    uart_init();
}

int uart_rx_ready(void)
{
    return (mmio_read(UART_FR) & UART_FR_RXFE) == 0u;
}

uint8_t uart_rx_byte(void)
{
    return (uint8_t)(mmio_read(UART_DR) & 0xFFu);   // bits 11:8 are error flags
}

// ---- protocol.h platform hooks ------------------------------------------------
int io_getc_timeout(uint32_t timeout_us)
{
    uint32_t start = timer_us();
    while (!uart_rx_ready()) {
        if ((uint32_t)(timer_us() - start) >= timeout_us)   // wrap-safe
            return -1;
    }
    return (int)uart_rx_byte();
}

void io_putc(uint8_t c)
{
    while (mmio_read(UART_FR) & UART_FR_TXFF) {
    }
    mmio_write(UART_DR, c);
}
