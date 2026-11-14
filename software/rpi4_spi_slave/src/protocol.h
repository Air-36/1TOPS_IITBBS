// =============================================================================
// protocol.h - host <-> Pi serial protocol (identical to the Pico firmware, so
// software/make_image.py --serial works unchanged):
//
//   host -> Pi : "PICO" | length (u32 little-endian) | <length bytes of boot stream>
//   Pi -> host : "OK"   stream stored and armed (SPI pointer = byte 0, rule R4)
//                "E2"   length 0 or larger than the buffer (old stream kept)
//                "E3"   timeout while receiving (stream DISARMED: no half image served)
//   host -> Pi : "STAT" -> "ARMED=<len> SENT=<bytes clocked out> REM=<len-sent>\n"
//   host -> Pi : "TIME" -> loop timing report (Pi 4 extension, see main.c)
//
// A 4-byte sliding window finds the keywords, so garbage before them is ignored.
// Timeouts as on the Pico: 1 s per length byte, 2 s per payload byte.
//
// Platform hooks (hw.c on the Pi, a mock in test/test_protocol.c):
//   int  io_getc_timeout(uint32_t us)   received byte 0..255, or -1 on timeout
//   void io_putc(uint8_t c)
// =============================================================================
#ifndef PROTOCOL_H
#define PROTOCOL_H

#include <stdint.h>

int  io_getc_timeout(uint32_t timeout_us);
void io_putc(uint8_t c);
void io_puts(const char *s);
void io_put_u32(uint32_t v);

#define PROTO_LEN_TIMEOUT_US   1000000u
#define PROTO_BYTE_TIMEOUT_US  2000000u

enum {
    PROTO_NONE = 0,     // nothing to do
    PROTO_LOAD,         // "PICO" + valid length received: caller must DISARM, then call
                        // proto_receive_payload(); *len_out = length
    PROTO_STAT,         // caller prints status
    PROTO_TIME          // caller runs the timing measurement
};

typedef struct {
    uint8_t *buf;       // stream buffer
    uint32_t cap;       // its size
    uint32_t win;       // last 4 received bytes (sliding window)
} proto_t;

void     proto_init(proto_t *p, uint8_t *buf, uint32_t cap);

// Feed one received byte. For "PICO" this also reads the 4 length bytes (blocking,
// with timeout) and replies "E2"/"E3" itself on error.
uint32_t proto_feed(proto_t *p, uint8_t c, uint32_t *len_out);

// After PROTO_LOAD (and after disarming the SPI slave): receive `len` payload bytes
// into the buffer. Returns 1 on success (caller arms, then calls proto_ack()), or 0
// after replying "E3" (caller keeps the slave disarmed).
int      proto_receive_payload(proto_t *p, uint32_t len);
void     proto_ack(void);

#endif
