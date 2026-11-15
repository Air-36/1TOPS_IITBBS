# =============================================================================
# build_basys3_bitstream.tcl - Basys 3: project (build_fpga.tcl) -> synthesis -> implementation
# -> bitstream, with the same run / timing checks as fpga/zcu102/build_zcu102.tcl.
# Run from anywhere:  vivado -mode batch -source fpga/build_basys3_bitstream.tcl   (or: make -C fpga build_fpga)
# Env: JOBS (default 8), ALLOW_TIMING_FAIL (default 0)
# Outputs (fpga/output/): tops_soc_basys3.bit, timing_summary.rpt, utilization.rpt
# =============================================================================
proc env_or {name default} {
  if {[info exists ::env($name)] && $::env($name) ne ""} { return $::env($name) }
  return $default
}
set here     [file dirname [file normalize [info script]]]
set out_dir  [file join $here "output"]
set jobs     [env_or JOBS 8]
set allow_tf [env_or ALLOW_TIMING_FAIL 0]
file mkdir $out_dir

source [file join $here "build_fpga.tcl"]          ;# creates and opens the project (top tops_soc_fpga_top)

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
    error "Timing NOT met (WNS $wns, WHS $whs). See fpga/output/timing_summary.rpt (ALLOW_TIMING_FAIL=1 to override)."
  }
}
set impl_dir [get_property DIRECTORY [get_runs impl_1]]
file copy -force [file join $impl_dir "tops_soc_fpga_top.bit"] [file join $out_dir "tops_soc_basys3.bit"]
puts "=========================================================================="
puts "Basys 3 build complete: [file join $out_dir tops_soc_basys3.bit]"
puts "=========================================================================="
