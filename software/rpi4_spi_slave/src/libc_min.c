// =============================================================================
// libc_min.c - the few C library functions a freestanding build can still need
// (the compiler may emit calls to them for struct copies / zeroing).
// Byte-wise on purpose: with the MMU off all data memory is Device memory, where
// unaligned accesses fault (the build also uses -mstrict-align).
// =============================================================================
#include <stddef.h>
#include <stdint.h>

void *memset(void *dst, int c, size_t n)
{
    uint8_t *d = (uint8_t *)dst;
    while (n--)
        *d++ = (uint8_t)c;
    return dst;
}

void *memcpy(void *dst, const void *src, size_t n)
{
    uint8_t *d = (uint8_t *)dst;
    const uint8_t *s = (const uint8_t *)src;
    while (n--)
        *d++ = *s++;
    return dst;
}

void *memmove(void *dst, const void *src, size_t n)
{
    uint8_t *d = (uint8_t *)dst;
    const uint8_t *s = (const uint8_t *)src;
    if (d < s) {
        while (n--)
            *d++ = *s++;
    } else if (d > s) {
        while (n--)
            d[n] = s[n];
    }
    return dst;
}
