/* link.ld - Raspberry Pi 4 bare-metal image, loaded by the firmware at 0x80000
   (config.txt: kernel_address=0x80000). The stack grows down from 0x80000. */
ENTRY(_start)

SECTIONS
{
    . = 0x80000;

    .text : {
        KEEP(*(.text.boot))        /* _start must be first */
        *(.text .text.*)
    }
    .rodata : ALIGN(8) { *(.rodata .rodata.*) }
    .data   : ALIGN(8) { *(.data .data.*) }

    .bss (NOLOAD) : ALIGN(16) {
        __bss_start = .;
        *(.bss .bss.*)
        *(COMMON)
        . = ALIGN(8);
        __bss_end = .;
    }

    /DISCARD/ : { *(.comment) *(.note*) *(.eh_frame*) }
}
