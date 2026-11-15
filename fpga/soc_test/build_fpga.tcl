# ==============================================================================
# build_fpga.tcl
# Vivado Automated Project Generation Script for 1TOPS SoC
# on Digilent Basys 3 (xc7a35tcpg236-1) with Dual-Protocol Hardware Debugger
#
# Usage:
#   cd fpga
#   ./run_build.sh
#   or directly:
#   cd fpga/build && vivado -mode batch -source ../build_fpga.tcl
# ==============================================================================

set script_dir [file dirname [file normalize [info script]]]
set build_dir  [file join $script_dir "build"]
set proj_name  "tops_soc_fpga"
set proj_dir   [file join $build_dir "vivado_project"]
set part_num   "xc7a35tcpg236-1"

if {[file exists [file join $script_dir ".." "source"]]} {
    set source_dir [file normalize [file join $script_dir ".." "source"]]
} else {
    set source_dir [file normalize [file join $script_dir ".." ".." "source"]]
}
set top_dir    [file normalize [file join $script_dir "top"]]
set constr_dir [file normalize [file join $script_dir "constrs"]]

puts "=========================================================================="
puts "Building Vivado Project for Digilent Basys 3: $proj_name"
puts "Target Device: $part_num"
puts "Output Directory: $proj_dir"
puts "Source Directory: $source_dir"
puts "=========================================================================="

# Ensure isolated build directory exists
file mkdir $build_dir

# 1. Close open project only if one exists
if {[llength [get_projects -quiet]] > 0} {
    puts "Closing currently open Vivado project..."
    close_project
}

# Destroy previous project folder if it exists
if {[file exists $proj_dir]} {
    puts "Destroying previous Vivado project folder: $proj_dir"
    file delete -force $proj_dir
}

# 2. Create fresh project in build/ directory
create_project $proj_name $proj_dir -part $part_num -force

# 3. Add configuration include paths (strictly from ../source)
set inc_dirs [list \
    [file normalize [file join $source_dir "components"]] \
    [file normalize [file join $source_dir "debugger"]] \
    [file normalize [file join $source_dir "main"]] \
    [file normalize [file join $source_dir "main" "soc"]] \
    [file normalize [file join $source_dir "uncore"]] \
    $top_dir]
set_property include_dirs $inc_dirs [get_filesets sources_1]
if {[llength [get_filesets -quiet sim_1]] > 0} {
    set_property include_dirs $inc_dirs [get_filesets sim_1]
}

# 4. Add Top-Level FPGA Wrapper
set top_wrapper [file join $top_dir "tops_soc_fpga_top.sv"]
if {[file exists $top_wrapper]} {
    add_files -norecurse -fileset sources_1 $top_wrapper
    puts "Added Top-Level FPGA Wrapper: $top_wrapper"
}

# 5. Add all SystemVerilog (.sv) and Verilog (.v) sources strictly from ../source/
set patterns [list \
    [file join $source_dir "components" "*.v"] \
    [file join $source_dir "debugger" "*.v"] \
    [file join $source_dir "debugger" "*.sv"] \
    [file join $source_dir "main" "*.v"] \
    [file join $source_dir "main" "soc" "*.v"] \
    [file join $source_dir "uncore" "*.sv"] \
]

set all_files {}
foreach pat $patterns {
    set match_files [glob -nocomplain $pat]
    foreach f $match_files {
        # Exclude simulation testbenches and FTDI stream generators
        if {[string match "*tb_*" $f] || [string match "*_stream.v" $f] || [string match "*/tb/*" $f]} {
            continue
        }
        lappend all_files $f
    }
}

if {[llength $all_files] > 0} {
    add_files -norecurse -fileset sources_1 [lsort -unique $all_files]
}

# 6. Set SystemVerilog file type on all .sv files
set sv_files [get_files -of_objects [get_filesets sources_1] -filter {NAME =~ "*.sv"}]
if {[llength $sv_files] > 0} {
    set_property file_type {SystemVerilog} $sv_files
}

# 7. Add Basys 3 Physical Constraints File
set xdc_file [file join $constr_dir "basys3.xdc"]
if {[file exists $xdc_file]} {
    add_files -fileset constrs_1 -norecurse $xdc_file
    puts "Added Basys 3 constraints: $xdc_file"
}

# 8. Set Top Module and Update Compile Order
set_property top tops_soc_fpga_top [get_filesets sources_1]
update_compile_order -fileset sources_1

# 9. Disable incremental synthesis/implementation to prevent missing .dcp checkpoint warnings
if {[llength [get_runs -quiet synth_1]] > 0} {
    catch {set_property auto_incremental_checkpoint 0 [get_runs synth_1]}
    catch {set_property incremental_checkpoint {} [get_runs synth_1]}
}
if {[llength [get_runs -quiet impl_1]] > 0} {
    catch {set_property auto_incremental_checkpoint 0 [get_runs impl_1]}
    catch {set_property incremental_checkpoint {} [get_runs impl_1]}
}

puts "=========================================================================="
puts "Vivado Project Created Successfully in Isolated Directory!"
puts "Project File: [file join $proj_dir $proj_name.xpr]"
puts "Top Module:   tops_soc_fpga_top"
puts "Constraints:  $xdc_file"
puts "  - Debugger UART : Onboard USB (B18/A18)"
puts "  - Debugger FT1248: PMOD JB (A14/A16/B15/B16)"
puts "  - Protocol Switch: SW0 (V17)"
puts "  - Uncore UART   : PMOD JA (J1/L2)"
puts "  - Clock         : 100 MHz (W5)"
puts "Ready for synthesis, implementation, and bitstream generation!"
puts "=========================================================================="
