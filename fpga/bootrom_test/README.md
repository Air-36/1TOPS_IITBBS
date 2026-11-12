# 1TOPS SoC FPGA Flow: BootROM & SPI Boot Test (Basys 3)

This directory contains the Digilent Basys 3 FPGA flow corresponding to the **`bootrom-flow`** branch code, including the external SPI boot PMOD interface for streaming firmware from an external host (e.g. Raspberry Pi Pico).

## Overview
* **Target Board**: Digilent Basys 3 (`xc7a35tcpg236-1`)
* **Clock**: 100 MHz on-board oscillator (W5) -> 50 MHz SoC clock via MMCM (`MMCME2_BASE`).
* **Reset**: Active-high pushbutton `btnC` (U18).
* **Boot Configuration**: Slide switch `SW1` (V16): `0` = Internal ROM, `1` = External SPI Boot.
* **SPI Boot Interface (PMOD JC, Top Row)**:
  * Connects directly to external SPI slave (e.g. Raspberry Pi Pico running `software/pico_spi_boot`):
  * **Pin 1 (K17)**: `spi_cs_n` (registered active-low chip select)
  * **Pin 2 (M18)**: `spi_mosi` (SoC master out -> Pico slave in)
  * **Pin 3 (N17)**: `spi_miso` (Pico slave out -> SoC master in, internal pull-up enabled)
  * **Pin 4 (P18)**: `spi_sclk` (SPI Mode 3 clock, CPOL=1, CPHA=1)
* **Debugger Dual-Interface**:
  * **UART Mode**: Dedicated debugger UART on micro-USB port (B18/A18) at 115200 baud.
  * **FT1248 Mode**: 1-bit FT1248 interface on PMOD JB (A14, A16, B15, B16).
  * **Mode Switch**: Slide switch `SW0` (V17): `0` = UART, `1` = FT1248.
* **Uncore Application UART**: 16550 UART on PMOD JA (J1/L2) for application console.
* **Status LEDs**:
  * `LED0` (U16): Core halted.
  * `LED1` (E19): `dbg_sel` indicator (SW0 state).
  * `LED15` (L1): Debugger RX activity / latched on `]` prompt character.

## Directory Structure
```
bootrom_test/
├── constrs/
│   └── basys3.xdc              # Physical constraints with PMOD JC SPI boot pin mappings & false paths
├── top/
│   └── tops_soc_fpga_top.sv    # Top-level FPGA wrapper with SPI boot interface & registered CS
├── build_fpga.tcl              # Automated Vivado project generation TCL script
├── run_build.sh                # Pushbutton build runner (creates build/vivado_project)
├── sim_step_and_clkdiv.sh      # Vivado XSIM simulation runner
├── test_step_and_clkdiv.py     # Automated simulation test driver
└── README.md
```

## How to Build
To synthesize and implement the BootROM test design in Vivado:
```bash
cd fpga/bootrom_test
./run_build.sh
```

## External Boot Workflow
1. Compile program image using `software/make_image.py`:
   ```bash
   python3 software/make_image.py --mode 1 --test <program.elf> --ext software/build/bootrom_ext.elf -o flash.bin --serial /dev/ttyACM0
   ```
2. Connect Raspberry Pi Pico to Basys 3 PMOD JC (Pins 1-4 and GND).
3. Set `SW1` to `1` (External SPI Boot).
4. Press `btnC` (Reset). The 1TOPS SoC clocks the SPI bus, receives the `"BOOT"` stream, copies instructions into IMEM/DMEM, and executes.
