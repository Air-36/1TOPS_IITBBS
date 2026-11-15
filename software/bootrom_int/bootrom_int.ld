OUTPUT_ARCH("riscv")
ENTRY(_rom_start)

/* Internal ROM per uncore.sv: 0x0000_1000 - 0x0000_1FFF (4 KB). RESET_PC must be 0x1000. */
MEMORY
{
  rom (rx) : ORIGIN = 0x00001000, LENGTH = 4K
}

/* One explicit load segment without FILEHDR/PHDRS: otherwise ld may put the ELF and program
   headers (plus padding) into the loadable segment below the code, and make_image.py would ship
   them over SPI (seen: ext ROM chunk started at 0x80007000 instead of 0x80007C00). */
PHDRS
{
  text PT_LOAD;
}

SECTIONS
{
  .text : {
    *(.text.rom)
    *(.text*)
    *(.rodata*)
  } > rom :text
}