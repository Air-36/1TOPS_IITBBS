# ==============================================================================
# set_baud_230400.S
# Program to dynamically configure UART Baud Rate to 230,400 Baud
# Target: 1TOPS SoC on Digilent Basys 3 (50 MHz Clock)
#
# Math:
#   Clock Frequency = 50,000,000 Hz
#   Target Baud     = 230,400 Baud
#   Divider         = 50,000,000 / 230,400 = 217 (0x00D9)
#   Target Register = 0x0B00_00E0 (DBG_UART_CLKDIV in core_debug_ahb)
# ==============================================================================

.section .text
.globl _start

_start:
    lui   a0, 0x0B000         # a0 = 0x0B00_0000 (Base of Debug MMIO)
    addi  a0, a0, 0x0E0       # a0 = 0x0B00_00E0 (Address of DBG_UART_CLKDIV)
    addi  a1, zero, 217       # a1 = 217 (0x00D9 = 230,400 baud at 50 MHz)
    sw    a1, 0(a0)           # Core stores 217 to DBG_UART_CLKDIV via AHB
    ebreak                   # Trigger hardware auto-halt breakpoint
loop:
    j     loop                # Trap in safety loop if execution resumes
