##################################################################################
## zcu102_si570.xdc - alternative clock: USER_SI570 (U42, 300 MHz power-up default, HP bank 64)
## Used when CLK_SRC=SI570 (define ZCU102_CLK_SI570). MMCM: 300 MHz x 4 / 24 = 50 MHz.
## Pin and IOSTANDARD lines are copied unchanged from the AMD ZCU102 Board User Guide
## UG1182 (v1.2), Appendix B "Master Constraints File Listing". Port names = UG1182 nets.
##################################################################################

set_property PACKAGE_PIN AL8 [get_ports "USER_SI570_P"]
set_property IOSTANDARD DIFF_SSTL12 [get_ports "USER_SI570_P"]
set_property PACKAGE_PIN AL7 [get_ports "USER_SI570_N"]
set_property IOSTANDARD DIFF_SSTL12 [get_ports "USER_SI570_N"]
create_clock -period 3.333 -name clk_si570 [get_ports "USER_SI570_P"]
