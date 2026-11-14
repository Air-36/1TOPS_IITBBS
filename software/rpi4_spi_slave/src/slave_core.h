// =============================================================================
// slave_core.h - software SPI-slave state machine (SPI mode 3, MSB first, 8-bit)
//
// Pure logic, no hardware access: the Pi 4 main loop (main.c) feeds it pin
// samples and performs the returned MISO action; the host unit test
// (test/test_slave_core.c) feeds it simulated samples. Same code in both.
//
// Bus (driven by the 1TOPS SoC, the master):
//   CS   : low for a whole image, high between images / when idle.
//   SCLK : idles HIGH (CPOL=1). Each bit: falling edge = leading edge, the slave
//          drives the next bit on MISO; rising edge = trailing edge, the SoC
//          samples MISO (CPHA=1). With CPHA=1 the first bit of a byte is driven
//          at that byte's FIRST falling edge.
//   Between bytes the SoC pauses (SCLK stays high, CS stays low).
//
// Agreed slave rules (bootrom_spi_plan.pdf):
//   R1 keep a pointer to the next unsent byte; when CS goes low, continue from it
//   R2 CS going low restarts the bit position only (fresh byte), not the pointer
//   R3 ignore SCLK while CS is high
//   R4 only a reload (slv_arm) resets the pointer to byte 0
//
// Timing rule (the reason for the split into "edge" and "bookkeeping" work):
//   On a falling edge, MISO must change before the following rising edge, i.e.
//   within half an SCLK period. So the edge path only shifts a register and
//   returns the action; the memory read of the NEXT byte (slv_finish_byte) is
//   done on a later sample, while SCLK is low or idle, which is at least a full
//   SCLK period before the next falling edge.
// =============================================================================
#ifndef SLAVE_CORE_H
#define SLAVE_CORE_H

#include <stdint.h>

// Force inlining: the Pi main loop keeps its spi_slave_t in registers only if no
// helper is ever called out of line (an out-of-line call needs the struct's address).
#if defined(__GNUC__) || defined(__clang__)
#define SLV_INLINE static inline __attribute__((always_inline))
#else
#define SLV_INLINE static inline
#endif

enum {
    SLV_NONE       = 0,   // leave MISO as it is
    SLV_DRIVE_LOW  = 1,   // drive MISO = 0
    SLV_DRIVE_HIGH = 2    // drive MISO = 1
};

typedef struct {
    const uint8_t *buf;   // armed stream
    uint32_t len;         // stream length (0 = not armed: MISO sends 0xFF)
    uint32_t ptr;         // R1: index of the byte being sent; == len when finished
    uint32_t cur;         // value of buf[ptr] (0xFF past the end)
    uint32_t bit;         // bits of `cur` already driven: 0..8 (8 = byte done, not yet advanced)
    uint32_t prev_sclk;   // SCLK level at the previous sample (edge detection)
} spi_slave_t;

// Value of the byte at ptr; past the end (or unarmed) the slave sends 0xFF, which is
// what a pulled-up MISO would give: a boot without a reload fails cleanly (bad magic).
SLV_INLINE void slv_load(spi_slave_t *s)
{
    s->cur = (s->ptr < s->len) ? (uint32_t)s->buf[s->ptr] : 0xFFu;
}

// R4: arm a (re)loaded stream; pointer back to byte 0.
SLV_INLINE void slv_arm(spi_slave_t *s, const uint8_t *buf, uint32_t len)
{
    s->buf = buf;
    s->len = len;
    s->ptr = 0;
    s->bit = 0;
    s->prev_sclk = 1u;      // SCLK idles high in mode 3
    slv_load(s);
}

// R1: a whole byte has been driven; move to the next one (memory read: off the edge path).
SLV_INLINE void slv_finish_byte(spi_slave_t *s)
{
    if (s->ptr < s->len)
        s->ptr++;
    s->bit = 0;
    slv_load(s);
}

// One sample while CS is HIGH (bus idle).
// R3: SCLK is ignored, but its level is tracked so that the first falling edge after
// CS goes low is detected correctly. R2: an unfinished byte restarts from its MSB on
// the next CS-low (the pointer does not move); a finished byte is completed first.
SLV_INLINE void slv_sample_idle(spi_slave_t *s, uint32_t sclk)
{
    if (s->bit == 8u)
        slv_finish_byte(s);
    else
        s->bit = 0;
    s->prev_sclk = sclk;
}

// One sample while CS is LOW (transfer active). `sclk` is 0 or 1.
// Returns SLV_DRIVE_LOW / SLV_DRIVE_HIGH on a falling edge (the caller must update
// MISO immediately), SLV_NONE otherwise.
SLV_INLINE uint32_t slv_sample_active(spi_slave_t *s, uint32_t sclk)
{
    uint32_t act = SLV_NONE;

    if (s->prev_sclk && !sclk) {
        // Falling edge: drive the next bit. bit == 8 here means the previous byte's
        // bookkeeping never ran (no sample between two edges = the loop was too slow);
        // complete it so that at least the byte order stays right.
        if (s->bit == 8u)
            slv_finish_byte(s);
        act = ((s->cur >> (7u - s->bit)) & 1u) ? SLV_DRIVE_HIGH : SLV_DRIVE_LOW;
        s->bit++;
    } else if (s->bit == 8u) {
        // Not an edge, and the last bit of the byte has been driven: advance now.
        slv_finish_byte(s);
    }
    s->prev_sclk = sclk;
    return act;
}

#endif
