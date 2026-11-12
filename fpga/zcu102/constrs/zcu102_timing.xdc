##################################################################################
## zcu102_timing.xdc - 1TOPS SoC on ZCU102 timing constraints
## The input clock is created in zcu102_clk125.xdc / zcu102_si570.xdc (one of them is
## added by build_zcu102.tcl). The 50 MHz SoC clock is derived by the MMCM, so Vivado
## generates its constraint automatically.
##################################################################################

## Asynchronous I/O false paths (same treatment as Basys 3, basys3.xdc section 8):
## buttons, switches, LEDs, serial lines and the PMOD links. SPI and FT1248 are slow
## links whose clock the SoC generates itself, and data is sampled half an SCLK period
## after it changes (>= 4 SoC clock cycles), so no external I/O timing is needed.
set_false_path -from [get_ports "CPU_RESET"]
set_false_path -from [get_ports "GPIO_DIP_SW*"]
set_false_path -from [get_ports "UART2_TXD_O_FPGA_RXD"]
set_false_path -from [get_ports "PMOD0_2"]
set_false_path -from [get_ports "PMOD0_6"]
set_false_path -from [get_ports "PMOD0_7"]
set_false_path -from [get_ports "PMOD1_0"]
set_false_path -to   [get_ports "GPIO_LED_*"]
set_false_path -to   [get_ports "UART2_RXD_I_FPGA_TXD"]
set_false_path -to   [get_ports "PMOD0_*"]
set_false_path -to   [get_ports "PMOD1_1"]
