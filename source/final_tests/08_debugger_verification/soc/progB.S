# Program B (uploaded by the debugger with 'U'): writes 0x600D to DRAM+0xC and spins
.section .text
.globl _start
_start:
    li   s0, 0x80010000
    li   t0, 0x600D
    sw   t0, 12(s0)
1:  j    1b
