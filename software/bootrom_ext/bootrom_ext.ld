OUTPUT_ARCH("riscv")
ENTRY(_start)

/* External boot ROM: top 1 KB of IMEM (IMEM = 0x8000_0000-0x8000_7FFF). The test program (link.ld)
   must stay below 0x80007C00 in mode 1. make_image.py checks this. */
MEMORY
{
  ext (rx) : ORIGIN = 0x80007C00, LENGTH = 1K
}

SECTIONS
{
  .text : {
    *(.text.start)
    *(.text*)
    *(.rodata*)
  } > ext
}