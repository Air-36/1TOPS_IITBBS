// =============================================================================
// boot.S - Raspberry Pi 4 (Cortex-A72, AArch64) bare-metal entry point.
//
// The Pi 4 firmware (start4.elf + the default armstub) loads kernel8.img at
// kernel_address (config.txt: 0x80000) and enters it on core 0, normally at EL2.
// Cores 1-3 normally stay parked in the armstub; they are also parked here, in
// case a different stub is used.
//
// 1. park cores 1-3
// 2. mask interrupts (none are used: the program is fully polled)
// 3. enable the instruction cache at the current EL. With the MMU off, data
//    accesses are uncached Device accesses, but instruction fetches may be
//    cached; without this, every instruction would be fetched from DRAM and the
//    SPI loop would be far too slow.
// 4. stack just below the image (0x80000, grows down), clear .bss, call main
// =============================================================================

.section ".text.boot", "ax"
.globl _start
_start:
    mrs     x1, mpidr_el1
    and     x1, x1, #0xFF               // Aff0 = core number
    cbz     x1, 2f
1:  wfe                                 // cores 1-3: park forever
    b       1b

2:  msr     daifset, #0xF               // mask D, A, I, F

    ic      iallu                       // invalidate the I-cache before enabling it
    dsb     sy
    isb
    mrs     x0, CurrentEL
    lsr     x0, x0, #2
    and     x0, x0, #3
    cmp     x0, #3
    b.eq    3f
    cmp     x0, #2
    b.eq    4f
    mrs     x2, sctlr_el1               // EL1
    orr     x2, x2, #(1 << 12)          // SCTLR.I
    msr     sctlr_el1, x2
    b       5f
3:  mrs     x2, sctlr_el3               // EL3 (only without an armstub)
    orr     x2, x2, #(1 << 12)
    msr     sctlr_el3, x2
    b       5f
4:  mrs     x2, sctlr_el2               // EL2 (normal case on the Pi 4)
    orr     x2, x2, #(1 << 12)
    msr     sctlr_el2, x2
5:  isb

    ldr     x0, =_start                 // stack grows down from the load address
    mov     sp, x0

    ldr     x0, =__bss_start            // clear .bss (8-byte aligned by link.ld)
    ldr     x1, =__bss_end
6:  cmp     x0, x1
    b.hs    7f
    str     xzr, [x0], #8
    b       6b

7:  bl      main
8:  wfe                                 // main never returns; just in case
    b       8b
