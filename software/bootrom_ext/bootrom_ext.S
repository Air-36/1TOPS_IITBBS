# bootrom_ext.S - external boot ROM (arrives over SPI in mode 1, runs from top of IMEM)
# Loads the test image (second image in the SPI stream) and jumps to its entry.

.equ DMEM_TOP, 0x80018000     # top of data RAM (0x8001_0000 + 32 KB)

.section .text.start, "ax"
.globl _start
_start:
    li   sp, DMEM_TOP
    call spi_init
    j    load_image

#include "loader.S"