##################################################################################
## zcu102_clk125.xdc - default clock: CLK_125 (U69 SI5341B, fixed 125 MHz, bank 47)
## Used when CLK_SRC=CLK125 (default). MMCM: 125 MHz x 8 / 20 = 50 MHz.
## Pin and IOSTANDARD lines are copied unchanged from the AMD ZCU102 Board User Guide
## UG1182 (v1.2), Appendix B "Master Constraints File Listing". Port names = UG1182 nets.
##################################################################################

set_property PACKAGE_PIN G21 [get_ports "CLK_125_P"]
set_property IOSTANDARD LVDS_25 [get_ports "CLK_125_P"]
set_property PACKAGE_PIN F21 [get_ports "CLK_125_N"]
set_property IOSTANDARD LVDS_25 [get_ports "CLK_125_N"]
create_clock -period 8.000 -name clk_125 [get_ports "CLK_125_P"]
