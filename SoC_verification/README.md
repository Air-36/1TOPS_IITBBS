# 1TOPS RISC-V SoC UVM Verification Framework

This directory (`SoC_verification/`) contains the complete SystemVerilog UVM verification environment for the **1TOPS RISC-V System-on-Chip (SoC)**, implementing the comprehensive verification plan described in [`coreless_soc_ahb_uvm_verification_plan.txt`](../coreless_soc_ahb_uvm_verification_plan.txt) and extending it to the **full chip with the RISC-V CPU core and bare-metal firmware execution**.

---

## 1. Verification Strategy & Architecture

The verification environment is architected in **three progressive verification tiers**:

1. **Level 1 — Standalone IP Unit Verification**:
   Isolates each uncore peripheral and accelerator IP to verify its register map, FIFO semantics, finite state machines, interrupt triggers, and protocol compliance:
   - GPIO APB (`gpio_apb.sv`) + Bidirectional GPIO VIP + APB VIP
   - CLINT APB (`clint_apb.sv`) + Real-time timer and software interrupt VIP
   - PLIC APB (`plic_apb.sv`) + Priority arbitration, threshold masking, and claim/complete VIP
   - System Controller APB (`sysctrl_apb.sv`) + Soft reset, boot status, vector remap, SYS_ID
   - Hardware Multiplier AHB Slave (`multiplier_ahb.v`) + Multiplicand/Multiplier registers & single-cycle pipeline
   - 16550 UART APB (`uart_apb.sv`) + Line control, divisor latches, FIFO status
   - SPI Controller APB (`spi_apb.sv`) + Baudrate divider, chip select modes, TX/RX FIFO status

2. **Level 2 — Whole SoC Coreless Verification (Without Masters)**:
   Verifies the uncore subsystem and internal interconnect fabric by decoupling the active bus masters (CPU and Debugger). The UVM **AHB-Lite Master VIP** is connected directly to the central AHB bus matrix, exercising all memory regions, address decoders, bridges, and peripheral interrupt routes through standard AMBA frontdoor transactions.

3. **Level 3 — Full SoC with RISC-V CPU Core Verification (Firmware + VIPs)**:
   Integrates the **full top-level SoC DUT (`riscv_soc_ahb.v`)** with the pipelined 5-stage RISC-V CPU core active and connected:
   - **Instruction & Data Memory**: The CPU fetches instructions from Instruction RAM (`0x8000_0000`) and operates on Data RAM (`0x8001_0000`).
   - **Cross-Compiled Bare-Metal Firmware**: Real C and RISC-V assembly programs (compiled using `xPack GNU RISC-V Embedded GCC`) run natively on the CPU.
   - **Interrupt Routing & Handling**: Core Local Interruptor (`MTimerInt` and `MSwInt`) and Platform-Level Interrupt Controller (`MExtInt` via GPIO/UART/SPI) are connected directly to the CPU's trap unit, exercising vector tables, ISRs, `mcause`, `mepc`, and `mret`.
   - **Peripheral Verification via VIPs**: While software runs on the core, external UVM VIPs (GPIO VIP, UART VIP Monitor, SPI Flash Behavioral Model, IRQ VIP Monitor) stimulate and observe peripheral pins concurrently.
   - **Multi-Channel Verification Handshake**: Mailbox status signature (`0x8001_7FFC`), SysCtrl scratchpad (`0x1008_0014`), and TOHOST (`0x8000_1000`) provide deterministic pass/fail telemetry to the UVM testbench and scoreboard.
   - **Dual Boot Modes**: Validates Boot Mode 0 (Internal ROM diagnostics) and Boot Mode 1 (SPI Flash Bootloader reading 32 bytes from external SPI Flash, remapping to IMEM, and jumping to execution).

```
+-----------------------------------------------------------------------------------------------------------------------+
|                                              UVM TESTBENCH ENVIRONMENT                                                |
|                                                                                                                       |
|  +--------------------+   +-------------------+   +--------------------+   +--------------------+   +---------------+ |
|  |     GPIO VIP       |   |     IRQ VIP       |   |      UART VIP      |   |  SPI Flash Model   |   | AHB/APB SVA   | |
|  | - 2-Way Handshake  |   | - Latency Monitor |   | - Char Stream Sniff|   | - W25Q Series Beh. |   | - Protocol    | |
|  | - Edge Detection   |   | - CLINT/PLIC Sinks|   | - Baud Checking    |   | - Preloaded Image  |   | - No Contention| |
|  +---------+----------+   +---------+---------+   +---------+----------+   +---------+----------+   +-------+-------+ |
+------------|------------------------|-----------------------|------------------------|--------------------------|-----+
             | (GPIO Pins [31:0])     | (MTimer/MSw/MExtInt)  | (UART TX/RX)           | (SPICLK/CS/MOSI/MISO)    |
             v                        v                       v                        v                          v
+-----------------------------------------------------------------------------------------------------------------------+
|                                                riscv_soc_ahb.v                                                        |
|                                                                                                                       |
|  +----------------------------------------------------+      +-----------------------------------------------------+  |
|  |                RISC-V CPU CORE                     |      |                    AHB-LITE BUS                     |  |
|  |  - 5-Stage RV32I Pipelined Core                    |      |  - Central Multi-Master / Multi-Slave Matrix        |  |
|  |  - Trap Unit: MTVEC, MEPC, MCAUSE, MSTATUS, MIE    |<---->|  - Pipelined Address & Data Phases                  |  |
|  |  - Interrupt Inputs: MTimerInt, MSwInt, MExtInt    |      +--------------------------+--------------------------+  |
|  +----------------------------------------------------+                                 |                             |
|                                                                                          v                             |
|  +-------------------------------------+  +-------------------------------------+  +--------------------------------+ |
|  |        Instruction RAM (32K)        |  |          Data RAM (32K)             |  |      Hardware Multiplier       | |
|  |            0x8000_0000              |  |           0x8001_0000               |  |          0x3000_0000           | |
|  +-------------------------------------+  +-------------------------------------+  +--------------------------------+ |
|                                                                                          |                             |
|  +-------------------------------------+  +-------------------------------------+        v                             |
|  |          Boot ROM (4K)              |  |       Core Debugger AHB             |  +--------------------------------+ |
|  |            0x0000_1000              |  |           0x0B00_0000               |  |     AHB-to-APB Bridge 3        | |
|  +-------------------------------------+  +-------------------------------------+  +----------------+---------------+ |
|                                                                                                     |                 |
+-----------------------------------------------------------------------------------------------------|-----------------+
                                                                                                      v
                                                                             +----------------------------------+
                                                                             |         APB PERIPHERALS          |
                                                                             |  Slot 0: CLINT    (0x0200_0000)  |
                                                                             |  Slot 1: PLIC     (0x0C00_0000)  |
                                                                             |  Slot 2: UART     (0x1000_0000)  |
                                                                             |  Slot 3: SPI      (0x1004_0000)  |
                                                                             |  Slot 4: GPIO     (0x1006_0000)  |
                                                                             |  Slot 5: SYSCTRL  (0x1008_0000)  |
                                                                             +----------------------------------+
```

---

## 2. Directory Structure

```
SoC_verification/
├── Makefile                          # Master Makefile for unit, coreless, and full SoC regressions
├── run_regression.sh                 # Master regression runner script (27 tests)
├── README.md                         # Comprehensive documentation (this file)
├── rtl/                              # Verilog / SystemVerilog SoC RTL snapshot
│   ├── components/                   # CPU execution datapath components
│   ├── debugger/                     # Core debugger, ADP control, FT1248, AHB mux
│   ├── main/                         # riscv_cpu.v, riscv_soc_ahb.v, multiplier_ahb.v
│   └── uncore/                       # Interconnect, RAM, ROM, bridge, and all APB peripherals
├── vip/                              # Reusable Universal Verification Components (UVCs)
│   ├── ahb_lite_vip/                 # AMBA 3 AHB-Lite Master VIP (Driver, Monitor, Sequencer, Agent)
│   ├── apb_vip/                      # AMBA 3 APB Master VIP (Driver, Monitor, Sequencer, Agent)
│   ├── gpio_vip/                     # General Purpose I/O Pin VIP (Driver, Monitor, Agent)
│   ├── irq_vip/                      # Interrupt Verification VIP (Monitor, Collector, Agent)
│   └── uart_vip/                     # 16550 UART Monitor VIP (Frame decode, baud sampling)
├── unit_tests/                       # Level 1: Standalone Peripheral Unit Testbenches
│   ├── gpio/                         # GPIO APB + GPIO VIP + APB VIP testbench
│   ├── clint/                        # CLINT APB + IRQ VIP (Timer & SW IRQs)
│   ├── plic/                         # PLIC APB + IRQ VIP (Priorities, Claim/Complete)
│   ├── sysctrl/                      # SysCtrl APB (Reset, Vectors, Remap, SYS_ID)
│   ├── multiplier/                   # Hardware Multiplier AHB Slave unit test
│   ├── uart/                         # 16550 UART APB unit testbench
│   └── spi/                          # SPI Controller APB unit testbench
├── soc_coreless/                     # Level 2: Whole Coreless SoC Verification (Without Masters)
│   ├── dut/
│   │   └── riscv_soc_ahb_coreless.sv # Coreless DUT wrapping uncore + multiplier + debug
│   ├── tb/
│   │   ├── tb_soc_coreless_top.sv    # Top-level testbench with VIP hookups
│   │   ├── ahb_protocol_checker.sv   # Formal SystemVerilog Assertions (SVA)
│   │   └── spi_flash_model.sv        # Behavioral SPI flash slave model
│   ├── env/                          # Coreless UVM environment, RAL model, Scoreboard, Coverage
│   └── tests/                        # 9 Coreless SoC integration tests
└── soc_full_core/                    # Level 3: Full SoC with RISC-V CPU Core Verification
    ├── bsp/                          # Board Support Package for Bare-Metal Firmware
    │   ├── soc_regs.h                # SoC memory-mapped registers, bitmasks & helpers
    │   ├── link.ld                   # Linker script (IRAM @ 0x80000000, DRAM @ 0x80010000)
    │   ├── crt0.s                    # Startup assembly, SP init, BSS clear, trap vector
    │   └── elf2mems.py               # Pure Python ELF segment extractor -> Verilog $readmemh .mem
    ├── firmware/                     # Bare-Metal C Programs & Preloaded Images
    │   ├── Makefile                  # Cross-compilation rules using riscv-none-elf-gcc
    │   ├── fw_boot_bringup.c         # Memory march, walking ones, scratchpad, multiplier
    │   ├── fw_gpio_vip.c             # GPIO output driving + VIP input polling handshake
    │   ├── fw_uart_stream.c          # 16550 UART string transmission to UART VIP
    │   ├── fw_spi_loopback.c         # SPI Controller & Flash 0x03 byte read & verify
    │   ├── fw_clint_timer_irq.c      # CLINT mtimecmp timer interrupt & ISR handling
    │   ├── fw_clint_sw_irq.c         # CLINT msip software interrupt & ISR handling
    │   ├── fw_plic_gpio_irq.c        # GPIO edge -> PLIC -> Core MExtInt -> Claim/Complete
    │   ├── fw_nested_irq_stress.c    # Robustness under nested timer/SW IRQs + memory/branch stress
    │   └── fw_all_periph_suite.c     # Comprehensive master suite (all peripherals + IRQs)
    ├── tb/
    │   ├── tb_soc_full_top.sv        # Top module instantiating riscv_soc_ahb & all VIPs
    │   ├── soc_ctrl_if.sv            # Test control interface (pass, fail, arm, boot_mode)
    │   ├── cpu_exec_monitor.sv       # Monitors AHB writes for Mailbox, Scratchpad, TOHOST
    │   ├── spi_flash_model.sv        # W25Q-series SPI Flash model with preloaded bootloader
    │   ├── ahb_protocol_checker.sv   # SVA protocol checkers for AHB bus
    │   └── apb_protocol_checker.sv   # SVA protocol checkers for APB bus
    ├── env/
    │   ├── soc_full_env.sv           # UVM Environment integrating GPIO, IRQ, UART VIPs
    │   ├── soc_full_scoreboard.sv    # Correlates CPU events, VIP transactions, IRQs, strings
    │   ├── soc_full_coverage.sv      # Functional coverage for boot modes, IRQs, GPIO, UART
    │   └── soc_full_env_pkg.sv       # Full SoC environment package
    └── tests/
        ├── soc_full_base_test.sv     # Base test with wait_for_completion and timeout logic
        ├── soc_full_bringup_test.sv  # Memory bringup and arithmetic verification
        ├── soc_full_gpio_test.sv     # GPIO VIP handshake test
        ├── soc_full_uart_test.sv     # UART character streaming test
        ├── soc_full_spi_test.sv      # SPI Flash command 0x03 read test
        ├── soc_full_clint_test.sv    # CLINT Timer and Software interrupt test
        ├── soc_full_plic_test.sv     # PLIC external interrupt routing test
        ├── soc_full_stress_test.sv   # Robustness under load & nested interrupt test
        ├── soc_full_boot_test.sv     # Boot Mode 0 (Internal ROM) and Boot Mode 1 (SPI Flash)
        ├── soc_full_suite_test.sv    # Comprehensive master integration test
        └── soc_full_tests_pkg.sv     # Full SoC tests package
```

---

## 3. SoC Memory Map

| Slave / Peripheral | Base Address | End Address | Bus | Description |
|:---|:---:|:---:|:---:|:---|
| **Boot ROM** | `0x0000_1000` | `0x0000_1FFF` | AHB | 4 KB On-chip Boot ROM (Dual-mode bootloader) |
| **CLINT** | `0x0200_0000` | `0x0200_FFFF` | APB | Core Local Interruptor (`MSIP`, `MTIMECMP`, `MTIME`) |
| **Core Debug AHB** | `0x0B00_0000` | `0x0B00_0FFF` | AHB | Debugger memory-mapped registers |
| **PLIC** | `0x0C00_0000` | `0x0FFF_FFFF` | APB | Platform-Level Interrupt Controller (Gateway, Claim) |
| **UART 16550** | `0x1000_0000` | `0x1000_0FFF` | APB | 16550-compatible Serial Controller (Byte-addressed) |
| **SPI Controller** | `0x1004_0000` | `0x1004_0FFF` | APB | SPI Flash Controller (SiFive FU540 register model) |
| **GPIO** | `0x1006_0000` | `0x1006_0FFF` | APB | 32-bit Bidirectional General-Purpose I/O |
| **SysCtrl** | `0x1008_0000` | `0x1008_0FFF` | APB | System Reset, Boot Mode, Remap, Device ID (`0x170950C1`) |
| **Multiplier Socket** | `0x3000_0000` | `0x30FF_FFFF` | AHB | Dedicated hardware multiply accelerator |
| **Instruction RAM** | `0x8000_0000` | `0x8000_7FFF` | AHB | 32 KB High-speed SRAM for program instructions |
| **Data RAM** | `0x8001_0000` | `0x8001_7FFF` | AHB | 32 KB High-speed SRAM for data, BSS, and stack |

---

## 4. Complete Verification Test Matrix (27 Tests)

### Level 1: Standalone IP Unit Tests (7 Tests)
| Test Target | Test Target Command | Key Scenarios Verified | Status |
|:---|:---|:---|:---:|
| `unit_gpio` | `make -C unit_tests/gpio run` | Reset defaults, output pin driving, VIP input patterns, edge interrupts, W1C clear. | **PASSED** |
| `unit_clint` | `make -C unit_tests/clint run` | Timer tick counting, `MTIMECMP` match triggering `MTimerInt`, MSIP triggering `MSwInt`. | **PASSED** |
| `unit_plic` | `make -C unit_tests/plic run` | Priority arbitration, threshold masking, `MExtInt` assertion, interrupt claim and complete. | **PASSED** |
| `unit_sysctrl` | `make -C unit_tests/sysctrl run` | SYS_ID verification (`0x170950C1`), soft core reset, reset vector update, ROM remap control. | **PASSED** |
| `unit_multiplier`| `make -C unit_tests/multiplier run` | Operand A/B loading, single-cycle 32-bit multiplication, boundary and zero multiplication. | **PASSED** |
| `unit_uart` | `make -C unit_tests/uart run` | Line status register checks (THRE/TEMT), baudrate divider configuration, character writes. | **PASSED** |
| `unit_spi` | `make -C unit_tests/spi run` | SPI clock divider configuration, FIFO status register checks, command transmission. | **PASSED** |

### Level 2: Coreless SoC Subsystem Tests (9 Tests)
| Test Target | Test Target Command | Key Scenarios Verified | Status |
|:---|:---|:---|:---:|
| `soc_reset` | `make -C soc_coreless test_reset` | Post-reset bus stability, default SYS_ID, and uncore telemetry signals. | **PASSED** |
| `soc_single_rw` | `make -C soc_coreless test_single_rw` | Single read/write operations to IRAM, DRAM, SysCtrl, and Multiplier socket. | **PASSED** |
| `soc_addr_decode`| `make -C soc_coreless test_addr_decode` | Exhaustive frontdoor read/write across all 11 address-mapped SoC slaves. | **PASSED** |
| `soc_gpio_vip` | `make -C soc_coreless test_gpio_vip` | End-to-end GPIO VIP pin driving, AHB readback, rising-edge detection, and W1C clear. | **PASSED** |
| `soc_clint_irq` | `make -C soc_coreless test_clint_irq` | End-to-end `MTimerInt` and `MSwInt` interrupt assertion and clearance through AHB. | **PASSED** |
| `soc_plic_irq` | `make -C soc_coreless test_plic_irq` | Peripheral event (GPIO) routing through PLIC to `MExtInt` at SoC boundary and claim read. | **PASSED** |
| `soc_remap` | `make -C soc_coreless test_remap` | Boot ROM address space (`0x0000_0000`) dynamically remapped to IRAM via SysCtrl register. | **PASSED** |
| `soc_stress` | `make -C soc_coreless test_stress` | Concurrent traffic streams to IRAM, DRAM, Multiplier, and asynchronous GPIO pin driving. | **PASSED** |
| `soc_all` | `make -C soc_coreless test_all_suite` | Master regression test suite executing all 8 integration phases sequentially. | **PASSED** |

### Level 3: Full SoC with RISC-V CPU Core Tests (11 Tests)
| Test Target | Test Target Command | Firmware Source | Key Scenarios Verified | Status |
|:---|:---|:---|:---|:---:|
| `full_bringup` | `make -C soc_full_core test_bringup` | `fw_boot_bringup.c` | Memory march (0x00, 0xFF, 0xAA, 0x55), walking ones/zeros, SysCtrl scratchpad, HW multiplier. | **PASSED** |
| `full_gpio` | `make -C soc_full_core test_gpio` | `fw_gpio_vip.c` | Core drives GPIO outputs; VIP samples pins and returns sequence; 2-way handshake verified. | **PASSED** |
| `full_uart` | `make -C soc_full_core test_uart` | `fw_uart_stream.c` | Core streams `"HELLO_1TOPS_RISCV_SOC_UART_OK\n"` to 16550 UART; UART VIP verifies string. | **PASSED** |
| `full_spi` | `make -C soc_full_core test_spi` | `fw_spi_loopback.c` | Core issues command 0x03 to SPI Flash; reads 4 bytes (`13 05 a0 02`) from behavioral model. | **PASSED** |
| `full_clint_timer`| `make -C soc_full_core test_clint_timer` | `fw_clint_timer_irq.c` | `mtimecmp` match fires `MTimerInt`; CPU trap unit vectors to ISR, clears timer, executes `mret`. | **PASSED** |
| `full_clint_sw` | `make -C soc_full_core test_clint_sw` | `fw_clint_sw_irq.c` | `msip` write fires `MSwInt`; CPU trap unit vectors to ISR, clears `msip`, executes `mret`. | **PASSED** |
| `full_plic` | `make -C soc_full_core test_plic` | `fw_plic_gpio_irq.c` | GPIO bit 3 rising edge from VIP -> PLIC -> CPU `MExtInt` -> Core ISR claims ID 2 and completes. | **PASSED** |
| `full_stress` | `make -C soc_full_core test_stress` | `fw_nested_irq_stress.c` | Intensive ALU & memory loops under continuous timer IRQs and software interrupts (27 IRQs verified). | **PASSED** |
| `full_boot_mode0`| `make -C soc_full_core test_boot_mode0`| Boot ROM Mode 0 | CPU boots at `0x0000_1000`, executes internal diagnostics, writes PASS to Scratchpad & TOHOST. | **PASSED** |
| `full_boot_mode1`| `make -C soc_full_core test_boot_mode1`| Boot ROM Mode 1 | CPU boots at `0x0000_1000`, issues SPI read to Flash, copies 32 bytes to IMEM, jumps & executes. | **PASSED** |
| `full_suite` | `make -C soc_full_core test_suite` | `fw_all_periph_suite.c` | Master integration suite: Multiplier + GPIO + UART (26 chars) + SPI Flash + Timer IRQ + PLIC IRQ. | **PASSED** |

---

## 5. Firmware Toolchain & Compilation

The full SoC tests use the **xPack GNU RISC-V Embedded GCC Toolchain (15.2.0-1)**.
Toolchain binaries are located at:
```
/home/23EC01043/tools/xpack-riscv-none-elf-gcc-15.2.0-1/bin/riscv-none-elf-gcc
/home/23EC01043/tools/xpack-riscv-none-elf-gcc-15.2.0-1/bin/riscv-none-elf-objdump
```

To compile all bare-metal firmware programs:
```bash
cd SoC_verification/soc_full_core/firmware
make all
```

This compiles each program with flags `-march=rv32i_zicsr -mabi=ilp32 -O1 -nostdlib -nostartfiles -T ../bsp/link.ld`, disassembles the binary to `.dis`, and runs `elf2mems.py` to extract instruction and data segments directly into Verilog `$readmemh` hexadecimal format (`_instr.mem` and `_data.mem`).

---

## 6. How to Run Verification

### 6.1 Prerequisites
QuestaSim 2023.4_5 (or compatible SystemVerilog simulator with UVM 1.1d/1.2 support):
```bash
module load mentor/questasim/2023.4_5
```

### 6.2 Running the Complete Automated Regression
Execute the master regression script from `SoC_verification/`:
```bash
cd SoC_verification
./run_regression.sh
```
This runs all 27 tests (7 IP Unit Tests, 9 Coreless SoC Tests, and 11 Full SoC with Core Tests), logging output to `regression_logs/` and displaying a real-time summary table.

### 6.3 Running via Master Makefile
From `SoC_verification/`:
```bash
# Run the complete 27-test regression:
make regression

# Run all 7 standalone peripheral IP unit tests:
make unit_all

# Run all 9 coreless SoC integration tests:
make soc_all

# Run all 11 full SoC with RISC-V core tests:
make full_all

# Run individual full SoC test:
make full_bringup
make full_gpio
make full_uart
make full_spi
make full_clint_timer
make full_clint_sw
make full_plic
make full_stress
make full_boot_mode0
make full_boot_mode1
make full_suite
```

### 6.4 Clean Build Artifacts
```bash
make clean
```
