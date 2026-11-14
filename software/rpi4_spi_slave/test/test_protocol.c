// =============================================================================
// test_protocol.c - host unit test of src/protocol.c (Pico-compatible serial
// protocol) with a mock UART. Mirrors the main.c call sequence:
//   ev = proto_feed(); on PROTO_LOAD: disarm, proto_receive_payload(), arm, proto_ack()
// =============================================================================
#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include "protocol.h"

// ---- mock UART: input queue (empty = timeout), captured output -------------------
static uint8_t in_q[300000]; static size_t in_len, in_pos;
static char out[4096];       static size_t out_len;

int io_getc_timeout(uint32_t timeout_us) { (void)timeout_us; return in_pos < in_len ? in_q[in_pos++] : -1; }
void io_putc(uint8_t c) { if (out_len < sizeof(out) - 1) out[out_len++] = (char)c; out[out_len] = 0; }

static void feed(const void *p, size_t n) { memcpy(in_q + in_len, p, n); in_len += n; }
static void feed_u32(uint32_t v) { uint8_t b[4] = {v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, v >> 24}; feed(b, 4); }
static void reset_io(void) { in_len = in_pos = out_len = 0; out[0] = 0; }

// ---- mirror of the main.c handling ------------------------------------------------
static uint8_t buf[96 * 1024];
static proto_t p;
static uint32_t armed_len; static int disarm_before_overwrite_ok;
static int n_stat, n_time;

static void pump(void)
{
    while (in_pos < in_len) {
        uint32_t len = 0;
        uint32_t ev = proto_feed(&p, in_q[in_pos++], &len);
        if (ev == PROTO_LOAD) {
            armed_len = 0;                                    // disarm
            disarm_before_overwrite_ok = (armed_len == 0);
            if (proto_receive_payload(&p, len)) { armed_len = len; proto_ack(); }
        } else if (ev == PROTO_STAT) n_stat++;
        else if (ev == PROTO_TIME) n_time++;
    }
}

static int fails, checks;
#define CHECK(c, ...) do { checks++; if (c) { printf("  [PASS] " __VA_ARGS__); printf("\n"); } \
                           else { fails++; printf("  [FAIL] " __VA_ARGS__); printf("  (out=\"%s\")\n", out); } } while (0)

int main(void)
{
    printf("=== test_protocol: Pico-compatible serial protocol (src/protocol.c) ===\n");
    proto_init(&p, buf, sizeof buf);
    uint8_t img[5000]; for (int i = 0; i < 5000; i++) img[i] = (uint8_t)(i * 7 + 3);

    // 1. garbage, then a valid load (with bytes that look like CR/LF/'P' inside the payload)
    reset_io(); img[10] = 0x0A; img[11] = 0x0D; img[12] = 'P';
    feed("xyzPIC", 6); feed("PICO", 4); feed_u32(5000); feed(img, 5000);
    pump();
    CHECK(strcmp(out, "OK") == 0 && armed_len == 5000 && memcmp(buf, img, 5000) == 0,
          "1. garbage + PICO + 5000 B (incl. 0x0A/0x0D/'P') -> \"OK\", armed, buffer exact");
    CHECK(disarm_before_overwrite_ok, "   slave disarmed before the buffer is overwritten");

    // 2. length 0 and oversized -> E2, previous stream kept
    reset_io(); feed("PICO", 4); feed_u32(0); pump();
    CHECK(strcmp(out, "E2") == 0 && armed_len == 5000, "2. length 0 -> \"E2\", old stream kept");
    reset_io(); feed("PICO", 4); feed_u32(96 * 1024 + 1); pump();
    CHECK(strcmp(out, "E2") == 0 && armed_len == 5000, "   length > 96 KB -> \"E2\", old stream kept");

    // 3. truncated length / payload -> E3, slave stays disarmed
    reset_io(); feed("PICO", 4); feed("\x10\x00", 2); pump();
    CHECK(strcmp(out, "E3") == 0, "3. length timeout -> \"E3\"");
    reset_io(); feed("PICO", 4); feed_u32(100); feed(img, 40); pump();
    CHECK(strcmp(out, "E3") == 0 && armed_len == 0, "   payload timeout -> \"E3\", slave DISARMED (no half image served)");

    // 4. STAT / TIME keywords, also directly after another load
    reset_io(); feed("STAT", 4); feed("TIME", 4); pump();
    CHECK(n_stat == 1 && n_time == 1, "4. STAT and TIME recognised");

    // 5. back-to-back loads: second replaces the first (R4: reload)
    reset_io(); feed("PICO", 4); feed_u32(16); feed(img, 16); feed("PICO", 4); feed_u32(8); feed(img + 100, 8); pump();
    CHECK(strcmp(out, "OKOK") == 0 && armed_len == 8 && memcmp(buf, img + 100, 8) == 0,
          "5. two loads back to back -> \"OKOK\", second stream armed");

    // 6. a payload containing "STAT"/"PICO" is NOT interpreted (window reset after load)
    reset_io(); uint8_t tricky[12]; memcpy(tricky, "PICOSTATTIME", 12);
    feed("PICO", 4); feed_u32(12); feed(tricky, 12); pump();
    CHECK(strcmp(out, "OK") == 0 && armed_len == 12 && n_stat == 1 && n_time == 1,
          "6. keywords inside a payload are data, not commands");

    printf("=== RESULT: %s (%d checks, %d failures) ===\n", fails ? "FAILED" : "ALL PASS", checks, fails);
    return fails ? 1 : 0;
}
