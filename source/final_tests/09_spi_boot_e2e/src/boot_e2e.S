# boot_e2e.S - test program for the SPI boot end-to-end suite (09_spi_boot_e2e)
#
# Linked with software/link.ld, so the ELF has TWO load segments:
#   .text (+ .rodata) -> instruction RAM 0x8000_0000   (expect_tbl lives here)
#   .data             -> data RAM        0x8001_0000   (data_tbl lives here)
# make_image.py therefore emits two chunks, one per RAM window, which exercises the loader's
# multi-chunk path and both halves of its bounds check.
#
# The program compares data_tbl (data RAM chunk) word by word against expect_tbl (instruction
# RAM chunk). Both come from the same source table, so they match only if both chunks were
# copied completely and to the right addresses. It then writes:
#   0x600D_B007            to RESULT_ADDR on success
#   0xBAD0_0000 | index    to RESULT_ADDR on the first mismatching word
# and spins. RESULT_ADDR is not the loader's error word (0x8001_7FFC).
#
# No stack, no .bss (the loader copies only stored bytes; it does not zero memory), and it
# never writes its own tables, so it can be re-run from RAM after a debugger core reset.
# It stays far below 0x8000_7C00, so it can also be loaded behind the second-stage ROM (mode 1).

.equ RESULT_ADDR, 0x80014000
.equ PASS_WORD,   0x600DB007
.equ FAIL_BASE,   0xBAD00000
.equ NWORDS,      16

.macro TABLE
    .word 0x00000000, 0xFFFFFFFF, 0xA5A5A5A5, 0x5A5A5A5A
    .word 0x01234567, 0x89ABCDEF, 0xDEADBEEF, 0xCAFEBABE
    .word 0x1709C0DE, 0x80010000, 0x80007C00, 0x0000E1E2
    .word 0x13579BDF, 0x2468ACE0, 0x0F0F0F0F, 0xF00DF00D
.endm

    .section .text._start, "ax"
    .globl _start
_start:
    la   t0, data_tbl            # data RAM copy
    la   t1, expect_tbl          # instruction RAM copy
    li   t2, NWORDS
    li   t3, 0                   # word index
1:  lw   t4, 0(t0)
    lw   t5, 0(t1)
    bne  t4, t5, fail
    addi t0, t0, 4
    addi t1, t1, 4
    addi t3, t3, 1
    bne  t3, t2, 1b

    li   t0, RESULT_ADDR
    li   t1, PASS_WORD
    sw   t1, 0(t0)
2:  j    2b

fail:
    li   t0, RESULT_ADDR
    li   t1, FAIL_BASE
    or   t1, t1, t3
    sw   t1, 0(t0)
3:  j    3b

    .section .rodata
    .balign 4
expect_tbl:
    TABLE

    .section .data
    .balign 4
data_tbl:
    TABLE
