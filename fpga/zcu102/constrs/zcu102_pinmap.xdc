##################################################################################
## zcu102_pinmap.xdc - 1TOPS SoC on ZCU102
## Board I/O used by top/tops_soc_zcu102_top.sv (Basys 3 basys3.xdc equivalent).
## Pin and IOSTANDARD lines are copied unchanged from the AMD ZCU102 Board User Guide
## UG1182 (v1.2), Appendix B "Master Constraints File Listing". Port names = UG1182 nets.
##################################################################################

## 2. CPU reset pushbutton SW20 (active high)   (Basys: btnC U18)
set_property PACKAGE_PIN AM13 [get_ports "CPU_RESET"]
set_property IOSTANDARD LVCMOS33 [get_ports "CPU_RESET"]

## 3. GPIO DIP switch SW13 (active high): position 1 = dbg_sel, position 2 = boot_mode   (Basys: SW0 V17 / SW1 V16)
set_property PACKAGE_PIN AN14 [get_ports "GPIO_DIP_SW0"]
set_property IOSTANDARD LVCMOS33 [get_ports "GPIO_DIP_SW0"]
set_property PACKAGE_PIN AP14 [get_ports "GPIO_DIP_SW1"]
set_property IOSTANDARD LVCMOS33 [get_ports "GPIO_DIP_SW1"]

## 4. CP2108 channel 2 PL-side UART (micro-USB J83, bank 49): debugger UART   (Basys: on-board USB-UART B18/A18)
set_property PACKAGE_PIN E13 [get_ports "UART2_TXD_O_FPGA_RXD"]
set_property IOSTANDARD LVCMOS33 [get_ports "UART2_TXD_O_FPGA_RXD"]
set_property PACKAGE_PIN F13 [get_ports "UART2_RXD_I_FPGA_TXD"]
set_property IOSTANDARD LVCMOS33 [get_ports "UART2_RXD_I_FPGA_TXD"]

## 5. PMOD0 J55 (bank 47): [0..3] SPI boot (J55.1/.3/.5/.7), [4..7] FT1248 (J55.2/.4/.6/.8)   (Basys: SPI on PMOD JC, FT1248 on PMOD JB)
set_property PACKAGE_PIN A20 [get_ports "PMOD0_0"]
set_property IOSTANDARD LVCMOS33 [get_ports "PMOD0_0"]
set_property PACKAGE_PIN B20 [get_ports "PMOD0_1"]
set_property IOSTANDARD LVCMOS33 [get_ports "PMOD0_1"]
set_property PACKAGE_PIN A22 [get_ports "PMOD0_2"]
set_property IOSTANDARD LVCMOS33 [get_ports "PMOD0_2"]
set_property PACKAGE_PIN A21 [get_ports "PMOD0_3"]
set_property IOSTANDARD LVCMOS33 [get_ports "PMOD0_3"]
set_property PACKAGE_PIN B21 [get_ports "PMOD0_4"]
set_property IOSTANDARD LVCMOS33 [get_ports "PMOD0_4"]
set_property PACKAGE_PIN C21 [get_ports "PMOD0_5"]
set_property IOSTANDARD LVCMOS33 [get_ports "PMOD0_5"]
set_property PACKAGE_PIN C22 [get_ports "PMOD0_6"]
set_property IOSTANDARD LVCMOS33 [get_ports "PMOD0_6"]
set_property PACKAGE_PIN D21 [get_ports "PMOD0_7"]
set_property IOSTANDARD LVCMOS33 [get_ports "PMOD0_7"]

## 6. PMOD1 J87 (bank 47): [0] UARTSin (J87.1), [1] UARTSout (J87.3) - application UART   (Basys: PMOD JA J1/L2)
set_property PACKAGE_PIN D20 [get_ports "PMOD1_0"]
set_property IOSTANDARD LVCMOS33 [get_ports "PMOD1_0"]
set_property PACKAGE_PIN E20 [get_ports "PMOD1_1"]
set_property IOSTANDARD LVCMOS33 [get_ports "PMOD1_1"]

## 7. GPIO LEDs DS37..DS44 (active high)   (Basys: LED0/LED1/LED15)
set_property PACKAGE_PIN AG14 [get_ports "GPIO_LED_0"]
set_property IOSTANDARD LVCMOS33 [get_ports "GPIO_LED_0"]
set_property PACKAGE_PIN AF13 [get_ports "GPIO_LED_1"]
set_property IOSTANDARD LVCMOS33 [get_ports "GPIO_LED_1"]
set_property PACKAGE_PIN AE13 [get_ports "GPIO_LED_2"]
set_property IOSTANDARD LVCMOS33 [get_ports "GPIO_LED_2"]
set_property PACKAGE_PIN AJ14 [get_ports "GPIO_LED_3"]
set_property IOSTANDARD LVCMOS33 [get_ports "GPIO_LED_3"]
set_property PACKAGE_PIN AJ15 [get_ports "GPIO_LED_4"]
set_property IOSTANDARD LVCMOS33 [get_ports "GPIO_LED_4"]
set_property PACKAGE_PIN AH13 [get_ports "GPIO_LED_5"]
set_property IOSTANDARD LVCMOS33 [get_ports "GPIO_LED_5"]
set_property PACKAGE_PIN AH14 [get_ports "GPIO_LED_6"]
set_property IOSTANDARD LVCMOS33 [get_ports "GPIO_LED_6"]
set_property PACKAGE_PIN AL12 [get_ports "GPIO_LED_7"]
set_property IOSTANDARD LVCMOS33 [get_ports "GPIO_LED_7"]

## 8. Pulls (as on Basys 3 / the nanosoc PMOD0 setup)
set_property PULLUP   true [get_ports "PMOD0_0"]   ;# spi_cs_n idle high (no false CS while configuring)
set_property PULLDOWN true [get_ports "PMOD0_1"]   ;# spi_mosi
set_property PULLUP   true [get_ports "PMOD0_2"]   ;# spi_miso: no Pico -> 0xFF bytes -> loader error 0xE1
set_property PULLUP   true [get_ports "PMOD0_3"]   ;# spi_sclk idle high (mode 3)
set_property PULLUP   true [get_ports "PMOD0_4"]   ;# ft1248_clk
set_property PULLUP   true [get_ports "PMOD0_5"]   ;# ft1248_ss_n
set_property PULLUP   true [get_ports "PMOD0_6"]   ;# ft1248_miso / RXF#
set_property PULLUP   true [get_ports "PMOD0_7"]   ;# ft1248_miosio
set_property PULLUP   true [get_ports "PMOD1_0"]   ;# UARTSin idle high
set_property PULLUP   true [get_ports "UART2_TXD_O_FPGA_RXD"] ;# debugger UART RX idle high
