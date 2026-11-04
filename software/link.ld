OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
  imem (rx)  : ORIGIN = 0x80000000, LENGTH = 32K
  dmem (rwx) : ORIGIN = 0x80010000, LENGTH = 32K
}

SECTIONS
{
  .text : {
    *(.text._start)
    *(.text*)
    *(.rodata*)
  } > imem

  .data : {
    *(.data*)
    *(.sdata*)
  } > dmem

  .bss : {
    __bss_start = .;
    *(.bss*)
    *(.sbss*)
    __bss_end = .;
  } > dmem

  . = ALIGN(8);
  /* Stack will be placed at the end of dmem by crt0 */
}
