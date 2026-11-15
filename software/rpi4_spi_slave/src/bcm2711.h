// =============================================================================
// bcm2711.h - Raspberry Pi 4 (BCM2711) peripheral registers used by this program.
// Addresses are ARM physical addresses in the default "low peripheral" mode
// (config.txt must NOT set arm_peri_high=1): peripherals at 0xFE00_0000.
// Sources: BCM2711 ARM Peripherals (GPIO, PL011 UART, System Timer chapters).
// The MMU is off, so every data access to these addresses is Device-nGnRnE
// (strictly ordered, uncached): plain volatile 32-bit accesses are sufficient.
// =============================================================================
#ifndef BCM2711_H
#define BCM2711_H

#include <stdint.h>

#define PERIPH_BASE        0xFE000000UL

// ---- GPIO --------------------------------------------------------------------
#define GPIO_BASE          (PERIPH_BASE + 0x200000UL)
#define GPFSEL(n)          (GPIO_BASE + 0x00UL + 4UL * (n))   // n = pin / 10, 3 bits per pin
#define GPSET0             (GPIO_BASE + 0x1CUL)               // write 1 = drive high (pins 0-31)
#define GPSET1             (GPIO_BASE + 0x20UL)               // pins 32-57
#define GPCLR0             (GPIO_BASE + 0x28UL)               // write 1 = drive low (pins 0-31)
#define GPCLR1             (GPIO_BASE + 0x2CUL)               // pins 32-57
#define GPLEV0             (GPIO_BASE + 0x34UL)               // pin levels, pins 0-31
#define GPIO_PUP_PDN(n)    (GPIO_BASE + 0xE4UL + 4UL * (n))   // BCM2711 pulls: n = pin / 16, 2 bits/pin

#define GPIO_FSEL_INPUT    0u
#define GPIO_FSEL_OUTPUT   1u
#define GPIO_FSEL_ALT0     4u

#define GPIO_PULL_NONE     0u
#define GPIO_PULL_UP       1u
#define GPIO_PULL_DOWN     2u

// ---- PL011 UART0 (routed to GPIO14/15 with ALT0) -------------------------------
#define UART0_BASE         (PERIPH_BASE + 0x201000UL)
#define UART_DR            (UART0_BASE + 0x00UL)
#define UART_FR            (UART0_BASE + 0x18UL)
#define UART_IBRD          (UART0_BASE + 0x24UL)
#define UART_FBRD          (UART0_BASE + 0x28UL)
#define UART_LCRH          (UART0_BASE + 0x2CUL)
#define UART_CR            (UART0_BASE + 0x30UL)
#define UART_IMSC          (UART0_BASE + 0x38UL)
#define UART_ICR           (UART0_BASE + 0x44UL)

#define UART_FR_BUSY       (1u << 3)
#define UART_FR_RXFE       (1u << 4)    // RX FIFO empty
#define UART_FR_TXFF       (1u << 5)    // TX FIFO full
#define UART_LCRH_FEN      (1u << 4)    // FIFOs enabled
#define UART_LCRH_WLEN8    (3u << 5)    // 8 data bits
#define UART_CR_UARTEN     (1u << 0)
#define UART_CR_TXE        (1u << 8)
#define UART_CR_RXE        (1u << 9)

// ---- System timer: free-running 1 MHz counter --------------------------------
#define SYSTMR_BASE        (PERIPH_BASE + 0x003000UL)
#define SYSTMR_CLO         (SYSTMR_BASE + 0x04UL)

static inline uint32_t mmio_read(uintptr_t addr)              { return *(volatile uint32_t *)addr; }
static inline void     mmio_write(uintptr_t addr, uint32_t v) { *(volatile uint32_t *)addr = v; }

#endif
