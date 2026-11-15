# hw_program.tcl - program an FPGA through a (remote) hw_server.
# Env: BITFILE, HW_SERVER (host:port), DEVICE (pattern for get_hw_devices, e.g. xc7a35t* or xczu9*)
set bit $::env(BITFILE)
set srv $::env(HW_SERVER)
set pat [expr {[info exists ::env(DEVICE)] ? $::env(DEVICE) : "xc7a35t*"}]
if {![file exists $bit]} { puts "ERROR: $bit not found"; exit 1 }
open_hw_manager
connect_hw_server -url $srv
puts "Using bitstream: [file normalize $bit] ([file size $bit] bytes, [clock format [file mtime $bit] -format {%Y-%m-%d %H:%M}])"
set tgts [get_hw_targets -quiet]
puts "JTAG targets seen by hw_server $srv: [expr {[llength $tgts] ? $tgts : {NONE}}]"
if {[llength $tgts] == 0} {
  puts "ERROR: hw_server on $srv is reachable, but it sees no JTAG cable / board. On that PC check:"
  puts "  - board powered (power switch ON, power LED lit); USB cable in the PROG/JTAG port and in that PC"
  puts "  - the USB cable is a data cable (not charge-only)"
  puts "  - Digilent/Xilinx cable drivers installed (Windows: Device Manager shows 'USB Serial Converter A/B')"
  puts "  - no other program holds the cable (Adept, WaveForms, a local Vivado Hardware Manager)"
  puts "  - then restart hw_server there and re-run"
  exit 1
}
open_hw_target [lindex $tgts 0]
set dev [lindex [get_hw_devices $pat] 0]
if {$dev eq ""} { puts "ERROR: no $pat device in the JTAG chain on $srv"; exit 1 }
current_hw_device $dev
set_property PROGRAM.FILE $bit $dev
program_hw_devices $dev
refresh_hw_device $dev
# DONE flag: the property name differs between families (7-series: REGISTER.IR.BIT5_DONE).
# program_hw_devices already fails on a configuration error; this is a second check.
set done ""
foreach p {REGISTER.IR.BIT5_DONE REGISTER.CONFIG_STATUS.BIT14_DONE_PIN} {
  set done [get_property -quiet $p $dev]
  if {$done ne ""} break
}
if {$done eq "0"} { puts "ERROR: DONE not set after programming"; exit 1 }
puts "PROGRAM OK: $dev <- $bit"
close_hw_manager
