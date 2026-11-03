# ==============================================================================
# Vivado RTL Schematic Elaborate Script for 1TOPS SoC (rv32_core)
# ==============================================================================

set script_dir [file dirname [file normalize [info script]]]
set proj_file [file join $script_dir "rv32_core_schematic" "rv32_core_schematic.xpr"]

# Open or create project if not already open
if {[current_project -quiet] eq ""} {
    if {![file exists $proj_file]} {
        puts "Project file not found. Running create_project.tcl..."
        source [file join $script_dir "create_project.tcl"]
    } else {
        puts "Opening existing Vivado project: $proj_file"
        open_project $proj_file
    }
}

# Set top module to top wrapper
set_property top tops_soc_wrapper [get_filesets sources_1]
update_compile_order -fileset sources_1

puts "=========================================================================="
puts "Elaborating RTL Design for Schematic Viewer..."
puts "Top Module: tops_soc_wrapper"
puts "=========================================================================="

synth_design -rtl -name rtl_1

puts "=========================================================================="
puts "RTL Schematic Elaboration Complete!"
puts "You can now view and inspect the hierarchy schematic in Vivado GUI."
puts "=========================================================================="
