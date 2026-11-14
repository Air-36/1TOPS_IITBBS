// =============================================================================
// diag.c - Raspberry Pi 4 UART diagnostic (bench bring-up only; not the SPI slave).
//
// Build: make diag  ->  build/diag/kernel8.img (copy it over kernel8.img on the SD card).
// Reads the UART/GPIO registers exactly as the firmware left them, then loops forever
// over three ways of driving GPIO 14 (TXD, header pin 8), printing one status line
// every 300 ms, 3 s per phase:
//   A  mini UART (UART1, GPIO14/15 ALT5) with the firmware's settings
//   B  PL011 (UART0, GPIO14/15 ALT0) with the firmware's settings
//   C  PL011 programmed like hw.c (48 MHz clock assumed, IBRD 26 / FBRD 3 -> 115200)
// The ACT LED is on during A and C and off during B, so a 3 s on/off rhythm shows
// that the loop is running even if no text arrives.
// Every TX wait is bounded, so a dead UART cannot hang the loop.
// =============================================================================
#include <stdint.h>
#include "bcm2711.h"

#define AUX_BASE      (PERIPH_BASE + 0x215000UL)
#define AUX_ENABLES   (AUX_BASE + 0x04UL)
#define AUX_MU_IO     (AUX_BASE + 0x40UL)
#define AUX_MU_IER    (AUX_BASE + 0x44UL)
#define AUX_MU_IIR    (AUX_BASE + 0x48UL)
#define AUX_MU_LCR    (AUX_BASE + 0x4CUL)
#define AUX_MU_MCR    (AUX_BASE + 0x50UL)
#define AUX_MU_LSR    (AUX_BASE + 0x54UL)
#define AUX_MU_CNTL   (AUX_BASE + 0x60UL)
#define AUX_MU_BAUD   (AUX_BASE + 0x68UL)

#define FSEL_ALT0     4u
#define FSEL_ALT5     2u
#define ACT_LED       42u

static uint32_t now_us(void) { return mmio_read(SYSTMR_CLO); }

static void delay_us(uint32_t us)
{
    uint32_t t0 = now_us();
    while ((uint32_t)(now_us() - t0) < us) {
    }
}

static void fsel(uint32_t pin, uint32_t fn)
{
    uintptr_t reg = GPFSEL(pin / 10u);
    uint32_t sh = (pin % 10u) * 3u;
    mmio_write(reg, (mmio_read(reg) & ~(7u << sh)) | ((fn & 7u) << sh));
}

static void led(int on) { mmio_write(on ? GPSET1 : GPCLR1, 1u << (ACT_LED - 32u)); }

// ---- output through the selected UART (bounded waits) ----------------------------
static int use_mini;

static void putc_any(char c)
{
    uint32_t t0 = now_us();
    if (use_mini) {
        while (!(mmio_read(AUX_MU_LSR) & 0x20u) && (uint32_t)(now_us() - t0) < 2000u) {
        }
        mmio_write(AUX_MU_IO, (uint32_t)(uint8_t)c);
    } else {
        while ((mmio_read(UART_FR) & UART_FR_TXFF) && (uint32_t)(now_us() - t0) < 2000u) {
        }
        mmio_write(UART_DR, (uint32_t)(uint8_t)c);
    }
}

static void puts_any(const char *s) { while (*s) putc_any(*s++); }

static void hex_any(const char *name, uint32_t v)
{
    static const char hx[] = "0123456789abcdef";
    puts_any(" ");
    puts_any(name);
    puts_any("=");
    for (int i = 28; i >= 0; i -= 4)
        putc_any(hx[(v >> i) & 15u]);
}

// ---- register snapshot taken at entry, before this program touches anything -------
static uint32_t s_el, s_fsel1, s_fsel3, s_auxen, s_mubaud, s_mucntl, s_mulcr;
static uint32_t s_cr, s_ibrd, s_fbrd, s_lcrh, s_fr;

static void line(char tag, const char *what)
{
    putc_any('\r');
    putc_any('\n');
    puts_any("DIAG ");
    putc_any(tag);
    puts_any(" ");
    puts_any(what);
    hex_any("EL", s_el);
    hex_any("FSEL1", s_fsel1);
    hex_any("FSEL3", s_fsel3);
    hex_any("AUXEN", s_auxen);
    hex_any("MUBAUD", s_mubaud);
    hex_any("MUCNTL", s_mucntl);
    hex_any("MULCR", s_mulcr);
    hex_any("U0CR", s_cr);
    hex_any("IBRD", s_ibrd);
    hex_any("FBRD", s_fbrd);
    hex_any("LCRH", s_lcrh);
    hex_any("FR", s_fr);
    hex_any("nowIBRD", mmio_read(UART_IBRD));
    hex_any("nowCR", mmio_read(UART_CR));
}

static void phase(char tag, const char *what)
{
    for (int i = 0; i < 10; i++) {          // 10 lines x 300 ms = 3 s
        line(tag, what);
        delay_us(300000u);
    }
}

int main(void)
{
    uint64_t el;
    __asm__ volatile("mrs %0, CurrentEL" : "=r"(el));
    s_el     = (uint32_t)((el >> 2) & 3u);
    s_fsel1  = mmio_read(GPFSEL(1));
    s_fsel3  = mmio_read(GPFSEL(3));
    s_auxen  = mmio_read(AUX_ENABLES);
    s_mubaud = mmio_read(AUX_MU_BAUD);
    s_mucntl = mmio_read(AUX_MU_CNTL);
    s_mulcr  = mmio_read(AUX_MU_LCR);
    s_cr     = mmio_read(UART_CR);
    s_ibrd   = mmio_read(UART_IBRD);
    s_fbrd   = mmio_read(UART_FBRD);
    s_lcrh   = mmio_read(UART_LCRH);
    s_fr     = mmio_read(UART_FR);

    fsel(ACT_LED, 1u);                      // output

    for (;;) {
        // A: mini UART as the firmware left it (enable it with 115200 @ 500 MHz if it is off)
        if (!(mmio_read(AUX_ENABLES) & 1u) || mmio_read(AUX_MU_BAUD) == 0u) {
            mmio_write(AUX_ENABLES, mmio_read(AUX_ENABLES) | 1u);
            mmio_write(AUX_MU_CNTL, 0u);
            mmio_write(AUX_MU_IER, 0u);
            mmio_write(AUX_MU_LCR, 3u);     // 8 bit
            mmio_write(AUX_MU_MCR, 0u);
            mmio_write(AUX_MU_BAUD, 541u);  // 500 MHz / (8 * 542) = 115314
            mmio_write(AUX_MU_IIR, 0xC6u);  // clear FIFOs
            mmio_write(AUX_MU_CNTL, 3u);    // RX + TX on
        }
        fsel(14u, FSEL_ALT5);
        fsel(15u, FSEL_ALT5);
        use_mini = 1;
        led(1);
        phase('A', "mini-uart fw-settings");
        delay_us(5000u);

        // B: PL011 as the firmware left it (only switch it on if it is off)
        fsel(14u, FSEL_ALT0);
        fsel(15u, FSEL_ALT0);
        use_mini = 0;
        if ((mmio_read(UART_CR) & 0x301u) != 0x301u)
            mmio_write(UART_CR, mmio_read(UART_CR) | 0x301u);
        led(0);
        phase('B', "pl011 fw-settings");
        delay_us(5000u);

        // C: PL011 programmed exactly like hw.c uart_init (48 MHz assumed)
        mmio_write(UART_CR, 0u);
        delay_us(2000u);
        mmio_write(UART_LCRH, 0u);
        mmio_write(UART_ICR, 0x7FFu);
        mmio_write(UART_IBRD, 26u);
        mmio_write(UART_FBRD, 3u);
        mmio_write(UART_LCRH, UART_LCRH_WLEN8 | UART_LCRH_FEN);
        mmio_write(UART_IMSC, 0u);
        mmio_write(UART_CR, UART_CR_UARTEN | UART_CR_TXE | UART_CR_RXE);
        led(1);
        phase('C', "pl011 hw.c-init 26/3");
        delay_us(5000u);
    }
}
