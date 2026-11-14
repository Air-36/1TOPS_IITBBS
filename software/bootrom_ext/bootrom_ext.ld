OUTPUT_ARCH("riscv")
ENTRY(_start)

/* External boot ROM: top 1 KB of IMEM (IMEM = 0x8000_0000-0x8000_7FFF). The test program (link.ld)
   must stay below 0x80007C00 in mode 1. make_image.py checks this. */
MEMORY
{
  ext (rx) : ORIGIN = 0x80007C00, LENGTH = 1K
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
    *(.text.start)
    *(.text*)
    *(.rodata*)
  } > ext :text
}