# bootrom_int.S - internal hardwired boot ROM (placed at reset vector, never sent over SPI)
# Mode 0: load [test image].  Mode 1: load [ext boot ROM image].  Both are "load_image".

.equ DMEM_TOP,       0x80018000     # top of data RAM (0x8001_0000 + 32 KB)
# The boot_mode pin (SW1) is latched by SYSCTRL: SYSCTRL_BOOT_STATUS (0x1008_0008) bit 0.
# This ROM does not read it: the mode is decided by what Python loads into the Pico.
.equ SYSCTRL_BOOT_STATUS, 0x10080008

.section .text.rom, "ax"
.globl _rom_start
_rom_start:
    li   sp, DMEM_TOP
    call spi_init
    # boot_mode is only read for info: the *flash content* differs per mode (Python loads
    # [test] for mode 0, [ext][test] for mode 1), so the internal ROM always does the same thing.
    # Optional check (not needed for boot): read the latched strap:
    #   li t0, SYSCTRL_BOOT_STATUS ; lw t1, 0(t0) ; andi t1, t1, 1
    j    load_image               # never returns: jumps to the image entry

#include "loader.S"