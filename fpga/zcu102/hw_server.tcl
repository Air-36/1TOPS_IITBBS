set bit $::env(BITFILE)
set srv $::env(HW_SERVER)
if {![file exists $bit]} { puts "ERROR: $bit not found"; exit 1 }

open_hw_manager
connect_hw_server -url $srv
open_hw_target
set dev [lindex [get_hw_devices xczu9*] 0]
if {$dev eq ""} { puts "ERROR: no xczu9 device in JTAG chain"; exit 1 }
current_hw_device $dev
set_property PROGRAM.FILE $bit $dev
program_hw_devices $dev
refresh_hw_device $dev
if {[get_property REGISTER.IR.BIT05_DONE $dev] != 1} { puts "ERROR: DONE not set"; exit 1 }
puts "PROGRAM OK"
close_hw_manager