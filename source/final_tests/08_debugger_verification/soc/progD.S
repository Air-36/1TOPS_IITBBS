# progD - SoC debugger verification program
#   DRAM+0x40 selects the scenario (written by the testbench before reset release)
#     0 : main loop (loads, stores, load-use, branches, jal/ret, lui, auipc)
#     1 : illegal instruction (SYSTEM funct3=100)       -> mcause 2
#     2 : ebreak                                        -> mcause 3
#     3 : ecall                                         -> mcause 11
#     4 : jump to a misaligned address                  -> mcause 0
#     5 : undefined opcode 0xFFFFFFFF                   -> should be mcause 2
#     6 : external interrupt enabled, spin              -> mcause 0x8000000B
#     7 : firmware writes the debugger UART divider (0x0B0000E0 = 24)
#   handler: DRAM+0x20 mcause, +0x24 mepc, +0x28 mtval, +0x2C trap count
#   scenarios 1..7 end with DRAM+0x44 = 0x600D, then spin incrementing DRAM+0
    .section .text
    .globl _start
_start:
    la   t0, handler
    csrw mtvec, t0
    li   t1, 0x5A5A1234
    csrw mscratch, t1
    li   s0, 0x80010000
    li   s1, 0
    li   s2, 0
    li   a0, 0x11111111
    li   a1, 0x22222222
    li   a2, 0x33333333
    li   a3, 0x44444444
    li   a4, 0x55555555
    li   a5, 0x66666666
    li   a6, 0x77777777
    li   a7, 0x88888888
    li   s4, 0x99999999
    li   s5, 0xAAAAAAAA
    li   s6, 0xBBBBBBBB
    li   s7, 0xCCCCCCCC
    li   s8, 0xDDDDDDDD
    li   s9, 0xEEEEEEEE
    li   s10, 0x12345678
    li   s11, 0x87654321
    lw   t0, 0x40(s0)
    li   t1, 1
    beq  t0, t1, t_illegal
    li   t1, 2
    beq  t0, t1, t_ebreak
    li   t1, 3
    beq  t0, t1, t_ecall
    li   t1, 4
    beq  t0, t1, t_misal
    li   t1, 5
    beq  t0, t1, t_undef
    li   t1, 6
    beq  t0, t1, t_irq
    li   t1, 7
    beq  t0, t1, t_baud
loop:
    addi s1, s1, 1
    sw   s1, 0(s0)
    lw   t2, 0(s0)
    add  s3, t2, zero
    bne  s3, s1, fail
    jal  ra, sub
    andi t3, s1, 3
    beqz t3, skip
    addi s2, s2, 1
skip:
    lui  t4, 0x12345
    auipc gp, 0
    j    loop
sub:
    addi s2, s2, 2
    sw   s2, 4(s0)
    ret
fail:
    li   t2, 0xBAD
    sw   t2, 8(s0)
1:  j    1b

t_illegal:
    .word 0x00004073
    j    after
t_ebreak:
    ebreak
    j    after
t_ecall:
    ecall
    j    after
t_misal:
    la   t2, after
    addi t2, t2, 2
    jalr zero, 0(t2)
    j    after
t_undef:
    .word 0xFFFFFFFF
    j    after
t_irq:
    li   t2, 0x800
    csrw mie, t2
    csrsi mstatus, 8
    j    spin
t_baud:
    li   t2, 0x0B0000E0
    li   t3, 24
    sw   t3, 0(t2)
    j    after
after:
    li   t2, 0x600D
    sw   t2, 0x44(s0)
spin:
    addi s1, s1, 1
    sw   s1, 0(s0)
    j    spin

    .align 2
handler:
    csrr t3, mcause
    sw   t3, 0x20(s0)
    csrr t4, mepc
    sw   t4, 0x24(s0)
    csrr t5, mtval
    sw   t5, 0x28(s0)
    lw   t6, 0x2c(s0)
    addi t6, t6, 1
    sw   t6, 0x2c(s0)
    bltz t3, 2f
    addi t4, t4, 4
    csrw mepc, t4
2:  mret
