// =============================================================================
// protocol.c - host <-> Pi serial protocol (see protocol.h). No hardware access.
// =============================================================================
#include "protocol.h"

#define KW(a, b, c, d) (((uint32_t)(a) << 24) | ((uint32_t)(b) << 16) | ((uint32_t)(c) << 8) | (uint32_t)(d))
#define KW_PICO KW('P', 'I', 'C', 'O')
#define KW_STAT KW('S', 'T', 'A', 'T')
#define KW_TIME KW('T', 'I', 'M', 'E')

void io_puts(const char *s)
{
    while (*s)
        io_putc((uint8_t)*s++);
}

void io_put_u32(uint32_t v)
{
    char tmp[10];
    int n = 0;
    do {
        tmp[n++] = (char)('0' + (v % 10u));
        v /= 10u;
    } while (v != 0u);
    while (n > 0)
        io_putc((uint8_t)tmp[--n]);
}

void proto_init(proto_t *p, uint8_t *buf, uint32_t cap)
{
    p->buf = buf;
    p->cap = cap;
    p->win = 0;
}

uint32_t proto_feed(proto_t *p, uint8_t c, uint32_t *len_out)
{
    p->win = (p->win << 8) | (uint32_t)c;

    if (p->win == KW_STAT) {
        p->win = 0;
        return PROTO_STAT;
    }
    if (p->win == KW_TIME) {
        p->win = 0;
        return PROTO_TIME;
    }
    if (p->win != KW_PICO)
        return PROTO_NONE;

    p->win = 0;
    uint32_t len = 0;
    for (uint32_t i = 0; i < 4u; i++) {
        int b = io_getc_timeout(PROTO_LEN_TIMEOUT_US);
        if (b < 0) {
            io_puts("E3");                       // timeout reading the length
            return PROTO_NONE;
        }
        len |= (uint32_t)(b & 0xFF) << (8u * i); // little-endian
    }
    if (len == 0u || len > p->cap) {
        io_puts("E2");                           // invalid / oversized: old stream kept
        return PROTO_NONE;
    }
    *len_out = len;
    return PROTO_LOAD;
}

int proto_receive_payload(proto_t *p, uint32_t len)
{
    for (uint32_t i = 0; i < len; i++) {
        int b = io_getc_timeout(PROTO_BYTE_TIMEOUT_US);
        if (b < 0) {
            io_puts("E3");                       // timeout mid-payload: caller stays disarmed
            return 0;
        }
        p->buf[i] = (uint8_t)b;
    }
    return 1;
}

void proto_ack(void)
{
    io_puts("OK");
}
