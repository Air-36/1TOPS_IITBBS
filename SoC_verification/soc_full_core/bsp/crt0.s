/*
 * crt0.s - Startup code and trap handler for 1TOPS RISC-V SoC
 */

    .section .text.init
    .globl _start
    .type _start, @function

_start:
    /* Disable interrupts initially */
    csrw mie, zero
    csrw mip, zero

    /* Initialize Stack Pointer to top of Data RAM (0x80017FF0) */
    la sp, _stack_top

    /* Initialize Trap Vector */
    la t0, trap_vector_entry
    csrw mtvec, t0

    /* Clear BSS */
    la t0, _sbss
    la t1, _ebss
bss_clear_loop:
    bge t0, t1, bss_done
    sw zero, 0(t0)
    addi t0, t0, 4
    j bss_clear_loop
bss_done:

    /* Call main() */
    call main

    /* If main returns, evaluate exit code in a0 */
    beqz a0, test_passed

test_failed:
    /* Write failure code to mailbox and scratchpad */
    li t0, 0x80017FFC
    li t1, 0xDEADBEEF
    sw t1, 0(t0)

    li t0, 0x10080014
    slli a0, a0, 1
    ori  a0, a0, 1
    sw a0, 0(t0)

    li t0, 0x80001000
    sw a0, 0(t0)
fail_spin:
    wfi
    j fail_spin

test_passed:
    /* Write PASS signature */
    li t0, 0x80017FFC
    li t1, 0xCAFEBABE
    sw t1, 0(t0)

    li t0, 0x10080014
    li t1, 1
    sw t1, 0(t0)

    li t0, 0x80001000
    sw t1, 0(t0)
pass_spin:
    wfi
    j pass_spin


/*
 * Standard Trap Vector Entry
 */
    .section .text
    .align 4
    .globl trap_vector_entry
    .type trap_vector_entry, @function
trap_vector_entry:
    /* Allocate stack frame for registers */
    addi sp, sp, -64

    sw ra,  0(sp)
    sw t0,  4(sp)
    sw t1,  8(sp)
    sw t2, 12(sp)
    sw a0, 16(sp)
    sw a1, 20(sp)
    sw a2, 24(sp)
    sw a3, 28(sp)
    sw a4, 32(sp)
    sw a5, 36(sp)
    sw a6, 40(sp)
    sw a7, 44(sp)
    sw t3, 48(sp)
    sw t4, 52(sp)
    sw t5, 56(sp)
    sw t6, 60(sp)

    /* Read trap cause and mepc */
    csrr a0, mcause
    csrr a1, mepc

    /* Call C interrupt / exception dispatcher */
    call trap_dispatcher

    /* Restore registers */
    lw ra,  0(sp)
    lw t0,  4(sp)
    lw t1,  8(sp)
    lw t2, 12(sp)
    lw a0, 16(sp)
    lw a1, 20(sp)
    lw a2, 24(sp)
    lw a3, 28(sp)
    lw a4, 32(sp)
    lw a5, 36(sp)
    lw a6, 40(sp)
    lw a7, 44(sp)
    lw t3, 48(sp)
    lw t4, 52(sp)
    lw t5, 56(sp)
    lw t6, 60(sp)

    addi sp, sp, 64

    /* Return from trap */
    mret

