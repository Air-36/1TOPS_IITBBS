OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
  IRAM (rx) : ORIGIN = 0x80000000, LENGTH = 32K
  DRAM (rw) : ORIGIN = 0x80010000, LENGTH = 32K
}

SECTIONS
{
  . = ORIGIN(IRAM);

  .text.init : {
    *(.text.init)
  } > IRAM

  .text : {
    *(.text)
    *(.text.*)
  } > IRAM

  .rodata : {
    *(.rodata)
    *(.rodata.*)
    *(.srodata)
    *(.srodata.*)
  } > IRAM

  . = ORIGIN(DRAM);

  .data : {
    _sdata = .;
    *(.data)
    *(.data.*)
    *(.sdata)
    *(.sdata.*)
    _edata = .;
  } > DRAM AT > IRAM
  _sidata = LOADADDR(.data);

  .bss : {
    _sbss = .;
    *(.bss)
    *(.bss.*)
    *(.sbss)
    *(.sbss.*)
    *(COMMON)
    _ebss = .;
  } > DRAM

  . = ALIGN(16);
  _stack_bottom = .;
  _stack_top = ORIGIN(DRAM) + LENGTH(DRAM) - 16;

  .tohost (NOLOAD) : {
    *(.tohost)
  } > IRAM
}

