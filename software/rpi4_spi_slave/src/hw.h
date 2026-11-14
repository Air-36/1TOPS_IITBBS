// =============================================================================
// hw.h - Raspberry Pi 4 board support for the SPI-slave program: pins, GPIO,
// PL011 UART (host link), system timer, ACT LED.
// =============================================================================
#ifndef HW_H
#define HW_H

#include <stdint.h>
#include "bcm2711.h"

// ---- SPI pins (40-pin header). All on GPLEV0 (pins < 32). ---------------------
// Wiring to the SoC SPI master (Basys 3 PMOD JC / ZCU102 PMOD0 J55):
//   CS   SoC -> Pi  GPIO 24 (header pin 18)   Basys JC1 K17   ZCU102 J55.1 A20
//   MOSI SoC -> Pi  GPIO 22 (header pin 15)   Basys JC2 M18   ZCU102 J55.3 B20 (unused)
//   MISO Pi -> SoC  GPIO 23 (header pin 16)   Basys JC3 N17   ZCU102 J55.5 A22
//   SCLK SoC -> Pi  GPIO 25 (header pin 22)   Basys JC4 P18   ZCU102 J55.7 A21
//   GND             header pin 20 or 25       PMOD GND
#define PIN_MOSI   22u
#define PIN_MISO   23u
#define PIN_CS     24u
#define PIN_SCLK   25u
#define MISO_MASK  (1u << PIN_MISO)
#define CS_MASK    (1u << PIN_CS)

// ---- Host link: PL011 UART0 on GPIO 14 TXD (pin 8) / GPIO 15 RXD (pin 10) ------
#ifndef UART_CLK_HZ
#define UART_CLK_HZ  48000000u      // config.txt: init_uart_clock=48000000
#endif
#ifndef UART_BAUD
#define UART_BAUD    115200u        // must match make_image.py --baud (default 115200)
#endif

// ---- Status LED: Pi 4 green ACT LED (GPIO 42, active high) ---------------------
#define PIN_ACT_LED  42u

void     hw_init(void);
void     gpio_fsel(uint32_t pin, uint32_t fn);
void     gpio_pull(uint32_t pin, uint32_t pull);
void     led_set(int on);
uint32_t timer_us(void);           // free-running 1 MHz counter (wraps every ~71 min)
int      uart_rx_ready(void);
uint8_t  uart_rx_byte(void);       // only call when uart_rx_ready()

#endif
