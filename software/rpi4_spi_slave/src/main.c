// =============================================================================
// main.c - Raspberry Pi 4 bare-metal SPI-slave boot server for the 1TOPS SoC.
//
// Replaces the Pico (software/pico_spi_boot): same serial protocol (protocol.h),
// same slave rules R1-R4 (slave_core.h). The SoC is the SPI master (mode 3);
// this program bit-bangs the slave on GPIO in a tight polling loop on core 0
// with interrupts masked and the instruction cache on (boot.S), so its reaction
// time is fixed and short.
//
// Performance note: the MMU is off, so ALL data memory (stack, globals) is
// uncached Device memory and every load/store is slow. The SPI state therefore
// lives in a local `spi_slave_t` that is only passed to always-inline functions
// (no address escapes), so the compiler keeps it in registers. The CS-low path
// touches nothing but GPLEV0 (read) and GPSET0/GPCLR0 (write).
// =============================================================================
#include <stdint.h>
#include "hw.h"
#include "protocol.h"
#include "slave_core.h"

#define MAX_STREAM      (96u * 1024u)    // >= 1 KB ext ROM + 64 KB RAM image + headers
#define SPI_HALF_NS     2000u            // SoC SCLK 250 kHz (loader.S SCKDIV_VAL 99)

static uint8_t stream_buf[MAX_STREAM] __attribute__((aligned(16)));
static proto_t proto;

static void print_status(uint32_t len, uint32_t ptr)
{
    io_puts("ARMED=");  io_put_u32(len);
    io_puts(" SENT=");  io_put_u32(ptr);
    io_puts(" REM=");   io_put_u32(len - ptr);
    io_puts("\n");
}

static uint32_t per_op_ns(uint32_t elapsed_us, uint32_t n)
{
    return (uint32_t)(((uint64_t)elapsed_us * 1000u + n / 2u) / n);
}

// "TIME": measure the real loop speed on this board (only run while CS is high).
//   gplev0_read_ns : one GPIO level read
//   gpio_write_ns  : one MISO write (GPSET0)
//   loop_ns        : one iteration of the CS-low path (read + state machine)
//   worst_reaction : loop_ns + gpio_write_ns = latest MISO update after a falling edge
//   budget         : half an SCLK period; worst_reaction must be well below it
static void measure_timing(void)
{
    const uint32_t n = 200000u;
    uint32_t t0, rd_us, wr_us, loop_us;

    t0 = timer_us();
    for (uint32_t i = 0; i < n; i++)
        (void)mmio_read(GPLEV0);
    rd_us = timer_us() - t0;

    t0 = timer_us();
    for (uint32_t i = 0; i < n; i++)
        mmio_write(GPSET0, MISO_MASK);           // MISO stays high: harmless while CS is high
    wr_us = timer_us() - t0;

    spi_slave_t d;
    slv_arm(&d, stream_buf, 0);
    t0 = timer_us();
    for (uint32_t i = 0; i < n; i++) {
        uint32_t lev = mmio_read(GPLEV0);
        uint32_t a = slv_sample_active(&d, (lev >> PIN_SCLK) & 1u);
        if (a == SLV_DRIVE_HIGH)
            mmio_write(GPSET0, MISO_MASK);
        else if (a == SLV_DRIVE_LOW)
            mmio_write(GPCLR0, MISO_MASK);
    }
    loop_us = timer_us() - t0;
    mmio_write(GPSET0, MISO_MASK);

    uint32_t rd = per_op_ns(rd_us, n), wr = per_op_ns(wr_us, n), lp = per_op_ns(loop_us, n);
    uint32_t worst = lp + wr;
    io_puts("TIME gplev0_read_ns=");  io_put_u32(rd);
    io_puts(" gpio_write_ns=");       io_put_u32(wr);
    io_puts(" loop_ns=");             io_put_u32(lp);
    io_puts(" worst_reaction_ns=");   io_put_u32(worst);
    io_puts(" budget_ns=");           io_put_u32(SPI_HALF_NS);
    io_puts(worst * 2u <= SPI_HALF_NS ? " margin=OK\n" : " margin=LOW\n");
}

int main(void)
{
    hw_init();
    proto_init(&proto, stream_buf, MAX_STREAM);
    io_puts("\r\nRPI4-SPI-SLAVE ready: SPI mode 3 slave, CS=GPIO24 SCLK=GPIO25 MISO=GPIO23; "
            "send PICO+len+stream (make_image.py --serial)\r\n");

    spi_slave_t s;                 // lives in registers (see note at the top)
    slv_arm(&s, stream_buf, 0);    // not armed yet: MISO sends 0xFF
    uint32_t led = 0;

    for (;;) {
        uint32_t lev  = mmio_read(GPLEV0);
        uint32_t sclk = (lev >> PIN_SCLK) & 1u;

        if (lev & CS_MASK) {
            // ---------------- bus idle (CS high): all slow work happens here ----------
            slv_sample_idle(&s, sclk);

            uint32_t want = (s.len != 0u && s.ptr < s.len) ? 1u : 0u;  // ACT LED = armed, not yet sent
            if (want != led) {
                led = want;
                led_set((int)led);
            }

            if (uart_rx_ready()) {
                uint32_t len = 0;
                uint32_t ev = proto_feed(&proto, uart_rx_byte(), &len);
                if (ev == PROTO_LOAD) {
                    slv_arm(&s, stream_buf, 0);          // disarm: the buffer is about to change
                    if (proto_receive_payload(&proto, len)) {
                        slv_arm(&s, stream_buf, len);    // R4: pointer = 0
                        proto_ack();                     // "OK"
                    }
                } else if (ev == PROTO_STAT) {
                    print_status(s.len, s.ptr);
                } else if (ev == PROTO_TIME) {
                    measure_timing();
                }
            }
            continue;
        }

        // -------------------- transfer active (CS low): time-critical path ------------
        uint32_t a = slv_sample_active(&s, sclk);
        if (a == SLV_DRIVE_HIGH)
            mmio_write(GPSET0, MISO_MASK);
        else if (a == SLV_DRIVE_LOW)
            mmio_write(GPCLR0, MISO_MASK);
    }
}
