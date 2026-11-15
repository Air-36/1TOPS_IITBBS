# Program A (preloaded): self-checking loop. Any lost/duplicated instruction or corrupted
# load/store breaks an invariant and writes 0xBAD to DRAM+8 (fail flag), then spins.
#   DRAM+0 = counter (s1), DRAM+4 = checksum (s2), DRAM+8 = fail flag, s3 = shadow checksum
.section .text
.globl _start
_start:
    li   s0, 0x80010000
    li   s1, 0
    li   s2, 0
    li   s3, 0
    sw   zero, 8(s0)
loop:
    addi s1, s1, 1
    sw   s1, 0(s0)
    lw   t0, 0(s0)
    bne  t0, s1, fail
    add  s2, s2, s1
    sw   s2, 4(s0)
    lw   t1, 4(s0)
    bne  t1, s2, fail
    add  s3, s3, s1
    bne  s3, s2, fail
    j    loop
fail:
    li   t2, 0xBAD
    sw   t2, 8(s0)
1:  j    1b
