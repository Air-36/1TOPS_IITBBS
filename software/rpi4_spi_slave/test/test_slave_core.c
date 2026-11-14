// =============================================================================
// test_slave_core.c - host unit test of src/slave_core.h (the Pi 4 SPI-slave logic)
//
// Simulates, on a nanosecond timeline:
//   * the SoC SPI master in mode 3 (CS low per image, 8 falling/rising edges per
//     byte, idle gaps between bytes, CS high between images), sampling MISO at
//     every rising edge (with a small setup time), and
//   * the Pi: discrete polls of (CS, SCLK) every P ns (with jitter); each MISO
//     action takes effect L ns after the poll (GPIO write latency).
// and checks the bytes the master receives against the agreed rules R1-R4.
//
// Build/run:  make test   (host gcc; see ../Makefile)
// =============================================================================
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include "../src/slave_core.h"

typedef long long ns_t;

// ---------------------------------------------------------------- waveform ----
typedef struct { ns_t t; int cs; int sclk; } tr_t;          // bus state from time t on
typedef struct { ns_t t; int img; int idx; int bitpos; } smp_t; // master samples MISO at t

#define MAXTR  2000000
#define MAXSMP 1000000
static tr_t  tr[MAXTR];  static int ntr;
static smp_t smp[MAXSMP]; static int nsmp;

static uint32_t rng = 12345u;
static uint32_t rnd(void) { rng = rng * 1103515245u + 12345u; return (rng >> 8) & 0xFFFFFF; }
static ns_t rnd_range(ns_t lo, ns_t hi) { return hi <= lo ? lo : lo + (ns_t)(rnd() % (uint32_t)(hi - lo + 1)); }

static void add_tr(ns_t t, int cs, int sclk) { tr[ntr].t = t; tr[ntr].cs = cs; tr[ntr].sclk = sclk; ntr++; }

// Master script: a list of "images", each = number of bytes clocked with CS low,
// optionally aborted after `abort_bits` bits of its last byte (CS released mid-byte).
typedef struct { int nbytes; int abort_bits; } image_t;

// H = SCLK half period. Byte gaps random in [gmin, gmax] ns. CS-high gap between images.
static ns_t build_master(const image_t *im, int nim, ns_t H, ns_t gmin, ns_t gmax, ns_t cs_gap)
{
    ntr = nsmp = 0;
    ns_t t = 1000;
    add_tr(0, 1, 1);
    for (int i = 0; i < nim; i++) {
        add_tr(t, 0, 1);                     // CS low, SCLK idle high
        t += 2 * H;                          // CS-to-SCLK delay (cssck)
        for (int b = 0; b < im[i].nbytes; b++) {
            int bits = (b == im[i].nbytes - 1 && im[i].abort_bits) ? im[i].abort_bits : 8;
            for (int k = 0; k < bits; k++) {
                add_tr(t, 0, 0);             // falling edge: slave drives bit
                t += H;
                add_tr(t, 0, 1);             // rising edge: master samples
                smp[nsmp].t = t; smp[nsmp].img = i; smp[nsmp].idx = b; smp[nsmp].bitpos = k; nsmp++;
                t += H;
            }
            t += rnd_range(gmin, gmax);      // software gap between bytes (SCLK high)
        }
        t += H;                              // SCLK-to-CS delay (sckcs)
        add_tr(t, 1, 1);                     // CS high
        t += cs_gap;
    }
    return t;
}

// ---------------------------------------------------------------- Pi model ----
typedef struct { ns_t t; int v; } miso_ev_t;
static miso_ev_t mev[MAXSMP * 2]; static int nmev;

// reload_at[]: re-arm (R4) at the first idle poll at/after this time (-1 = none)
static void run_pi(spi_slave_t *s, ns_t t_end, ns_t P, ns_t jitter, ns_t L,
                   const uint8_t *buf, uint32_t len, ns_t reload_at)
{
    nmev = 0;
    mev[nmev].t = 0; mev[nmev].v = 1; nmev++;          // MISO initially high
    int ti = 0, reloaded = 0;
    for (ns_t t = 0; t < t_end; ) {
        while (ti + 1 < ntr && tr[ti + 1].t <= t) ti++;
        int cs = tr[ti].cs, sclk = tr[ti].sclk;
        if (cs) {
            if (reload_at >= 0 && !reloaded && t >= reload_at) { slv_arm(s, buf, len); reloaded = 1; }
            slv_sample_idle(s, (uint32_t)sclk);
        } else {
            uint32_t a = slv_sample_active(s, (uint32_t)sclk);
            if (a != SLV_NONE) { mev[nmev].t = t + L; mev[nmev].v = (a == SLV_DRIVE_HIGH); nmev++; }
        }
        t += P + (jitter ? rnd_range(-jitter, jitter) : 0);
        if (t <= 0) t = 1;
    }
}

// Reconstruct what the master received. setup: MISO must be stable this long before
// the rising edge (one 50 MHz SoC clock).
#define SETUP 20
static int received[64][4096];   // [image][byte]
static void master_receive(void)
{
    memset(received, 0, sizeof(received));
    int mi = 0;
    for (int i = 0; i < nsmp; i++) {
        while (mi + 1 < nmev && mev[mi + 1].t <= smp[i].t - SETUP) mi++;
        int v = mev[mi].v;
        received[smp[i].img][smp[i].idx] |= v << (7 - smp[i].bitpos);
    }
}

// ---------------------------------------------------------------- tests -------
static int fails = 0, checks = 0;
#define CHECK(c, ...) do { checks++; if (!(c)) { fails++; printf("  [FAIL] " __VA_ARGS__); printf("\n"); } } while (0)

static uint8_t stream[4096];

static int compare_image(int img, int nbytes, const uint8_t *exp, const char *name)
{
    for (int b = 0; b < nbytes; b++)
        if (received[img][b] != exp[b]) {
            printf("  [FAIL] %s: image %d byte %d got 0x%02x expected 0x%02x\n",
                   name, img, b, received[img][b], exp[b]);
            fails++; checks++;
            return 0;
        }
    checks++;
    return 1;
}

static void fill_stream(uint32_t n) { for (uint32_t i = 0; i < n; i++) stream[i] = (uint8_t)(rnd() & 0xFF); }

// 1. Basic: one image, 250 kHz (H = 2000 ns), realistic Pi poll/latency.
static void t_basic(void)
{
    spi_slave_t s; fill_stream(256); slv_arm(&s, stream, 256);
    image_t im[] = {{256, 0}};
    ns_t end = build_master(im, 1, 2000, 300, 3000, 5000);
    run_pi(&s, end, 200, 50, 300, stream, 256, -1);
    master_receive();
    if (compare_image(0, 256, stream, "basic 256 B @250kHz P=200 L=300"))
        printf("  [PASS] basic: 256 bytes @250 kHz, poll 200+/-50 ns, write latency 300 ns\n");
    CHECK(s.ptr == 256, "basic: pointer %u != 256", s.ptr);
}

// 2. R1/R2: two images (mode 1: ext ROM then test) - second continues from the pointer.
static void t_two_images(void)
{
    spi_slave_t s; fill_stream(300); slv_arm(&s, stream, 300);
    image_t im[] = {{120, 0}, {180, 0}};
    ns_t end = build_master(im, 2, 2000, 300, 3000, 20000);
    run_pi(&s, end, 200, 50, 300, stream, 300, -1);
    master_receive();
    int ok = compare_image(0, 120, stream, "two images: first") &
             compare_image(1, 180, stream + 120, "two images: second continues (R1)");
    if (ok) printf("  [PASS] R1/R2: second image (after CS high) continues at byte 120\n");
}

// 3. Past the end -> 0xFF (unloaded / exhausted stream fails cleanly with bad magic).
static void t_past_end(void)
{
    spi_slave_t s; fill_stream(10); slv_arm(&s, stream, 10);
    image_t im[] = {{14, 0}};
    ns_t end = build_master(im, 1, 2000, 300, 3000, 5000);
    run_pi(&s, end, 200, 50, 300, stream, 10, -1);
    master_receive();
    uint8_t exp[14]; memcpy(exp, stream, 10); memset(exp + 10, 0xFF, 4);
    if (compare_image(0, 14, exp, "past end"))
        printf("  [PASS] past the end of the stream the master reads 0xFF\n");
    CHECK(s.ptr == 10, "past end: pointer %u != 10", s.ptr);

    spi_slave_t u; slv_arm(&u, stream, 0);                  // never loaded
    image_t im2[] = {{4, 0}};
    end = build_master(im2, 1, 2000, 300, 3000, 5000);
    run_pi(&u, end, 200, 50, 300, stream, 0, -1);
    master_receive();
    uint8_t ff[4] = {0xFF, 0xFF, 0xFF, 0xFF};
    if (compare_image(0, 4, ff, "unarmed"))
        printf("  [PASS] unarmed slave sends 0xFF (SoC sees bad magic 0xFFFFFFFF -> E1)\n");
}

// 4. R4: reload between two images restarts at byte 0.
static void t_reload(void)
{
    spi_slave_t s; fill_stream(64); slv_arm(&s, stream, 64);
    image_t im[] = {{40, 0}, {40, 0}};
    ns_t end = build_master(im, 2, 2000, 300, 3000, 200000);
    // re-arm while CS is high between the images (time after the first image)
    ns_t t_first_end = 0;                       // time CS first returns high (end of image 0)
    for (int i = 1; i < ntr; i++) if (tr[i].cs == 1 && tr[i - 1].cs == 0) { t_first_end = tr[i].t; break; }
    run_pi(&s, end, 200, 50, 300, stream, 64, t_first_end + 1000);
    master_receive();
    int ok = compare_image(0, 40, stream, "reload: first") & compare_image(1, 40, stream, "reload: second restarts at 0 (R4)");
    if (ok) printf("  [PASS] R4: a reload between images restarts the stream at byte 0\n");
}

// 5. R2: CS released after 3 bits of byte 5 -> next CS-low resends byte 5 from its MSB.
static void t_abort_mid_byte(void)
{
    spi_slave_t s; fill_stream(32); slv_arm(&s, stream, 32);
    image_t im[] = {{6, 3}, {10, 0}};          // image 0: bytes 0-4 complete, byte 5 aborted after 3 bits
    ns_t end = build_master(im, 2, 2000, 300, 3000, 20000);
    run_pi(&s, end, 200, 50, 300, stream, 32, -1);
    master_receive();
    int ok = compare_image(0, 5, stream, "abort: bytes before") &
             compare_image(1, 10, stream + 5, "abort: byte 5 resent from MSB");
    if (ok) printf("  [PASS] R2: a byte cut short by CS high is resent whole on the next CS-low\n");
}

// 6. Timing margin: sweep poll period P and write latency L at 250 kHz and 1 MHz.
static void t_margin(void)
{
    printf("  Timing sweep (pass = all 512 bytes correct, jitter +/-25%% of P):\n");
    const ns_t Hs[] = {2000, 500};
    const char *hn[] = {"250 kHz (SCKDIV 99, H=2000 ns)", "1 MHz   (SCKDIV 24, H= 500 ns)"};
    const ns_t Ps[] = {50, 100, 200, 400, 800, 1200, 1600};
    const ns_t Ls[] = {50, 300, 600};
    for (int h = 0; h < 2; h++) {
        printf("    %s\n      L\\P ", hn[h]);
        for (unsigned p = 0; p < sizeof Ps / sizeof *Ps; p++) printf("%6lld", Ps[p]);
        printf("\n");
        for (unsigned l = 0; l < sizeof Ls / sizeof *Ls; l++) {
            printf("      %4lld", Ls[l]);
            for (unsigned p = 0; p < sizeof Ps / sizeof *Ps; p++) {
                spi_slave_t s; fill_stream(512); slv_arm(&s, stream, 512);
                image_t im[] = {{512, 0}};
                ns_t end = build_master(im, 1, Hs[h], 300, 3000, 5000);
                run_pi(&s, end, Ps[p], Ps[p] / 4, Ls[l], stream, 512, -1);
                master_receive();
                int ok = 1;
                for (int b = 0; b < 512; b++) if (received[0][b] != stream[b]) { ok = 0; break; }
                printf("%6s", ok ? "ok" : "FAIL");
                // Requirement checked: worst-case reaction (P + jitter + L) below H - SETUP must pass.
                if (Ps[p] + Ps[p] / 4 + Ls[l] < Hs[h] - SETUP - 50) {
                    checks++;
                    if (!ok) { fails++; printf("<-unexpected"); }
                }
            }
            printf("\n");
        }
    }
}

int main(void)
{
    printf("=== test_slave_core: Pi 4 software SPI slave (mode 3) vs simulated SoC master ===\n");
    t_basic();
    t_two_images();
    t_past_end();
    t_reload();
    t_abort_mid_byte();
    t_margin();
    printf("=== RESULT: %s (%d checks, %d failures) ===\n", fails ? "FAILED" : "ALL PASS", checks, fails);
    return fails ? 1 : 0;
}
