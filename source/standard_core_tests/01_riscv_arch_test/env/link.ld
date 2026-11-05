/* Linker script for 1TOPS riscv_cpu arch compliance tests
   Memory: 2 MB AHB-Lite RAM at 0x80000000 */

OUTPUT_ARCH("riscv")
ENTRY(rvtest_entry_point)

SECTIONS
{
  . = 0x80000000;
  .text.init : { *(.text.init) }
  . = ALIGN(0x1000);
  .tohost : { *(.tohost) }
  . = ALIGN(0x1000);
  .text : { *(.text) }
  . = ALIGN(0x1000);
  .data : { *(.data) *(.data.string) }
  .bss : { *(.bss) }
  _end = .;
}
