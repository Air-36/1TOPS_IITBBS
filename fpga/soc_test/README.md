# 1TOPS SoC FPGA Flow: SoC Test (Basys 3)

This directory contains the Digilent Basys 3 FPGA flow corresponding to the **`main`** branch code baseline (without the external SPI boot PMOD additions).

## Overview
* **Target Board**: Digilent Basys 3 (`xc7a35tcpg236-1`)
* **Clock**: 100 MHz on-board oscillator (W5) synthesized down to 50 MHz SoC clock via MMCM (`MMCME2_BASE`).
* **Reset**: Active-high pushbutton `btnC` (U18).
* **Debugger Dual-Interface**:
  * **UART Mode**: Dedicated debugger UART on micro-USB port (B18/A18) at 115200 baud.
  * **FT1248 Mode**: 1-bit FT1248 interface on PMOD JB (A14, A16, B15, B16).
  * **Mode Switch**: Slide switch `SW0` (V17): `0` = UART, `1` = FT1248.
* **Uncore Application UART**: 16550 UART on PMOD JA (J1/L2) for bare-metal C software / console output.
* **Status LEDs**:
  * `LED0` (U16): Core halted.
  * `LED1` (E19): `dbg_sel` indicator (SW0 state).
  * `LED15` (L1): Debugger RX activity / latched on `]` prompt character.

## Directory Structure
```
soc_test/
├── constrs/
│   └── basys3.xdc              # Physical pin and timing constraints (retaining main branch code)
├── top/
│   └── tops_soc_fpga_top.sv    # Top-level FPGA wrapper (retaining main branch code)
├── build_fpga.tcl              # Automated Vivado project generation TCL script
├── run_build.sh                # Pushbutton build runner (creates build/vivado_project)
├── sim_step_and_clkdiv.sh      # Vivado XSIM simulation runner for step controller & clkdiv
├── test_step_and_clkdiv.py     # Automated simulation test driver
└── README.md
```

## How to Build
To synthesize and implement the SoC test design in Vivado:
```bash
cd fpga/soc_test
./run_build.sh
```
This launches Vivado in batch mode, compiles RTL sources from `../../source`, sets constraints from `constrs/basys3.xdc`, and creates a fresh project in `build/vivado_project/`.

## How to Simulate
To run XSIM simulation of the hardware debugger and step controller:
```bash
cd fpga/soc_test
./sim_step_and_clkdiv.sh
```

