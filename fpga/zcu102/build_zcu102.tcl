# ==============================================================================
# build_zcu102.tcl
# Vivado build for the 1TOPS SoC on the AMD ZCU102 (xczu9eg-ffvb1156-2-e).
# PL-only design (no Zynq PS block), the same structure as the Basys 3 build
# (fpga/build_fpga.tcl): RTL from ../../source + top/tops_soc_zcu102_top.sv + constrs/.
#
# Usage (normally via the Makefile in this folder, on the server that has Vivado):
#   make build_fpga
#   or: mkdir -p build && cd build && vivado -mode batch -source ../build_zcu102.tcl
#
# Environment (all optional):
#   FPGA_PART         default xczu9eg-ffvb1156-2-e (makefile.targets, FPGA=zcu102)
#   CLK_SRC           CLK125 (default, 125 MHz LVDS_25 on G21/F21) or SI570 (300 MHz on AL8/AL7)
#   ENABLE_ILA        default 1 (ILA on SPI/UART/PC/status; probes in output/*.ltx)
#   JOBS              default 8
#   ALLOW_TIMING_FAIL default 0 (1 = keep the bitstream even with negative slack)
#
# Outputs (output/): tops_soc_zcu102.bit, tops_soc_zcu102.ltx (ILA), timing_summary.rpt,
#                    utilization.rpt
# ==============================================================================

proc env_or {name default} {
  if {[info exists ::env($name)] && $::env($name) ne ""} { return $::env($name) }
  return $default
}

set script_dir [file dirname [file normalize [info script]]]
set source_dir [file normalize [file join $script_dir ".." ".." "source"]]
set top_dir    [file join $script_dir "top"]
set constr_dir [file join $script_dir "constrs"]
set build_dir  [file join $script_dir "build"]
set out_dir    [file join $script_dir "output"]
set proj_name  "tops_soc_zcu102"
set proj_dir   [file join $build_dir "vivado_project"]
set top_name   "tops_soc_zcu102_top"

set part_num   [env_or FPGA_PART         "xczu9eg-ffvb1156-2-e"]
set clk_src    [string toupper [env_or CLK_SRC "CLK125"]]
set enable_ila [env_or ENABLE_ILA        1]
set jobs       [env_or JOBS              8]
set allow_tf   [env_or ALLOW_TIMING_FAIL 0]
if {$clk_src ni {CLK125 SI570}} { error "CLK_SRC must be CLK125 or SI570 (got $clk_src)" }

puts "=========================================================================="
puts "Building 1TOPS SoC for ZCU102"
puts "  Part    : $part_num"
puts "  Clock   : $clk_src -> MMCM -> 50 MHz"
puts "  ILA     : $enable_ila"
puts "  Source  : $source_dir"
puts "  Project : $proj_dir"
puts "=========================================================================="

file mkdir $build_dir
file mkdir $out_dir
if {[llength [get_projects -quiet]] > 0} { close_project }
if {[file exists $proj_dir]} { file delete -force $proj_dir }

# 1. Project
create_project $proj_name $proj_dir -part $part_num -force

# 2. RTL: SoC sources (same set and include paths as the Basys 3 build) + ZCU102 top
set inc_dirs [list \
  [file join $source_dir "components"] \
  [file join $source_dir "debugger"] \
  [file join $source_dir "main"] \
  [file join $source_dir "main" "soc"] \
  [file join $source_dir "uncore"] \
  $top_dir]
set_property include_dirs $inc_dirs [get_filesets sources_1]

set patterns [list \
  [file join $source_dir "components" "*.v"] \
  [file join $source_dir "debugger" "*.v"] \
  [file join $source_dir "debugger" "*.sv"] \
  [file join $source_dir "main" "*.v"] \
  [file join $source_dir "main" "soc" "*.v"] \
  [file join $source_dir "uncore" "*.sv"] ]
set rtl_files {}
foreach pat $patterns {
  foreach f [glob -nocomplain $pat] {
    if {[string match "*tb_*" $f] || [string match "*_stream.v" $f] || [string match "*/tb/*" $f]} { continue }
    lappend rtl_files $f
  }
}
if {[llength $rtl_files] == 0} { error "No RTL found under $source_dir" }
add_files -norecurse -fileset sources_1 [lsort -unique $rtl_files]
add_files -norecurse -fileset sources_1 [file join $top_dir "tops_soc_zcu102_top.sv"]
set sv_files [get_files -of_objects [get_filesets sources_1] -filter {NAME =~ "*.sv"}]
if {[llength $sv_files] > 0} { set_property file_type {SystemVerilog} $sv_files }

# 3. Verilog defines: clock source, ILA
set defines {}
if {$clk_src eq "SI570"} { lappend defines ZCU102_CLK_SI570 }
if {$enable_ila}         { lappend defines ZCU102_ILA }
if {[llength $defines] > 0} { set_property verilog_define $defines [get_filesets sources_1] }

# 4. Optional ILA (SPI + UART lines, PC, status), viewed from Vivado over hw_server
if {$enable_ila} {
  create_ip -name ila -vendor xilinx.com -library ip -module_name ila_boot
  set_property -dict [list \
    CONFIG.C_NUM_OF_PROBES {3} \
    CONFIG.C_PROBE0_WIDTH {8} \
    CONFIG.C_PROBE1_WIDTH {32} \
    CONFIG.C_PROBE2_WIDTH {8} \
    CONFIG.C_DATA_DEPTH {8192} \
  ] [get_ips ila_boot]
  generate_target all [get_files ila_boot.xci]
}

# 5. Constraints: board pins (UG1182), selected clock, timing
add_files -fileset constrs_1 -norecurse [file join $constr_dir "zcu102_pinmap.xdc"]
if {$clk_src eq "SI570"} {
  add_files -fileset constrs_1 -norecurse [file join $constr_dir "zcu102_si570.xdc"]
} else {
  add_files -fileset constrs_1 -norecurse [file join $constr_dir "zcu102_clk125.xdc"]
}
add_files -fileset constrs_1 -norecurse [file join $constr_dir "zcu102_timing.xdc"]

set_property top $top_name [get_filesets sources_1]
update_compile_order -fileset sources_1
catch {set_property auto_incremental_checkpoint 0 [get_runs synth_1]}
catch {set_property auto_incremental_checkpoint 0 [get_runs impl_1]}

# 6. Synthesis, implementation, bitstream
proc check_run {run} {
  set progress [get_property PROGRESS [get_runs $run]]
  set status   [get_property STATUS   [get_runs $run]]
  puts "$run: $status ($progress)"
  if {$progress ne "100%" || [string match "*ERROR*" $status] || [string match "*failed*" $status]} {
    error "$run did not complete: $status"
  }
}
launch_runs synth_1 -jobs $jobs
wait_on_run synth_1
check_run synth_1

launch_runs impl_1 -to_step write_bitstream -jobs $jobs
wait_on_run impl_1
check_run impl_1

# 7. Reports, timing check, outputs
open_run impl_1
report_timing_summary -file [file join $out_dir "timing_summary.rpt"]
report_utilization    -file [file join $out_dir "utilization.rpt"]
set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
set whs [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -hold]]
puts "Timing: WNS = $wns ns, WHS = $whs ns"
if {($wns ne "" && $wns < 0) || ($whs ne "" && $whs < 0)} {
  if {$allow_tf} {
    puts "WARNING: timing NOT met (WNS $wns, WHS $whs); continuing because ALLOW_TIMING_FAIL=1"
  } else {
    error "Timing NOT met (WNS $wns, WHS $whs). See output/timing_summary.rpt (ALLOW_TIMING_FAIL=1 to override)."
  }
}

set impl_dir [get_property DIRECTORY [get_runs impl_1]]
file copy -force [file join $impl_dir "${top_name}.bit"] [file join $out_dir "${proj_name}.bit"]
if {$enable_ila} { write_debug_probes -force [file join $out_dir "${proj_name}.ltx"] }

puts "=========================================================================="
puts "ZCU102 build complete. Outputs in $out_dir:"
foreach f [lsort [glob -nocomplain -directory $out_dir *]] { puts "  [file tail $f]" }
puts "Program the board through hw_server:  make stream_remote"
puts "=========================================================================="
