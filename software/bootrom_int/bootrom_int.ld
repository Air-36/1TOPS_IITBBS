OUTPUT_ARCH("riscv")
ENTRY(_rom_start)

/* Internal ROM per uncore.sv: 0x0000_1000 - 0x0000_1FFF (4 KB). RESET_PC must be 0x1000. */
MEMORY
{
  rom (rx) : ORIGIN = 0x00001000, LENGTH = 4K
}

SECTIONS
{
  .text : {
    *(.text.rom)
    *(.text*)
    *(.rodata*)
  } > rom
}