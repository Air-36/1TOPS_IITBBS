# 1TOPS RISC-V SoC UVM Verification Framework

This directory (`SoC_verification/`) contains the complete SystemVerilog UVM verification environment for the **1TOPS RISC-V System-on-Chip (SoC)**, implementing the comprehensive verification plan described in [`coreless_soc_ahb_uvm_verification_plan.txt`](../coreless_soc_ahb_uvm_verification_plan.txt).

---

## 1. Verification Strategy & Architecture

The verification environment is split into two primary tiers:
1. **IP Unit Verification (Level 1)**: Standalone UVM testbenches for individual peripheral IPs and accelerator blocks, isolating each module to verify its register map, state machines, interrupt behavior, and boundary operations.
2. **Whole SoC Coreless Verification (Levels 2 & 3)**: Subsystem-level testbench where internal active masters (RISC-V CPU and Hardware Debugger) are decoupled. The UVM **AHB-Lite Master VIP** is connected directly to the primary SoC internal bus interconnect, exercising all memory domains (Boot ROM, Instruction RAM, Data RAM), external accelerator sockets, and uncore APB peripherals through the frontdoor AMBA bus interface.

```
+--------------------------------------------------------------------------------------------------------+
|                                    UVM TESTBENCH ENVIRONMENT                                          |
|                                                                                                        |
|  +--------------------+   +-------------------+   +--------------------+   +-----------------------+   |
|  | AHB-Lite Master VIP|   |     GPIO VIP      |   |      IRQ VIP       |   |   AHB SVA Checker     |   |
|  | - Cycle-accurate   |   | - Pin Driver      |   | - Edge & Level Mon |   | - Protocol Assertions |   |
|  | - Burst/Waitstates |   | - Bidirectional   |   | - CLINT/PLIC Sinks |   | - Mutual Exclusion    |   |
|  +---------+----------+   +---------+---------+   +---------+----------+   +-----------+-----------+   |
+------------|------------------------|-----------------------|--------------------------|---------------+
             | (test_HADDR/WDATA/etc) | (GPIO pins)           | (MTimer/MSw/MExtInt)     |
             v                        v                       v                          v
+--------------------------------------------------------------------------------------------------------+
|                                      riscv_soc_ahb_coreless.sv                                         |
|                                                                                                        |
|  +-----------------------------------+     +---------------------------------------------------------+ |
|  |     Hardware Multiplier AHB       |     |                      uncore.sv                          | |
|  |        (0x3000_0000)              |     |  +---------------------+  +--------------------------+  | |
|  +-----------------------------------+     |  | Instruction RAM (32K)|  |     Data RAM (32K)       |  | |
|                                            |  |   (0x8000_0000)     |  |     (0x8001_0000)        |  | |
|  +-----------------------------------+     |  +---------------------+  +--------------------------+  | |
|  |       Core Debugger AHB Slave     |     |  +---------------------+  +--------------------------+  | |
|  |        (0x0B00_0000)              |     |  | Boot ROM (4K)       |  | AHB-to-APB Bridge 3      |  | |
|  +-----------------------------------+     |  |   (0x0000_1000)     |  | (Slots 0 to 5)           |  | |
|                                            |  +---------------------+  +------------+-------------+  | |
|                                            +----------------------------------------|----------------+ |
+-------------------------------------------------------------------------------------|------------------+
                                                                                      |
                                            +-----------------------------------------+
                                            |
                                            v
                    +-------------------------------------------------------------------+
                    |                          APB PERIPHERALS                          |
                    |  - CLINT (0x0200_0000): Software & Real-Time Timer Interrupts    |
                    |  - PLIC  (0x0C00_0000): Priority Gateway, Claim & Completion     |
                    |  - UART  (0x1000_0000): 16550 UART Model / Console Stream        |
                    |  - SPI   (0x1004_0000): SPI Controller + External Flash Slave     |
                    |  - GPIO  (0x1006_0000): Bidirectional Pins, Rise/Fall Detect     |
                    |  - SYSCTRL(0x1008_0000): Reset Control, Remap & Device ID         |
                    +-------------------------------------------------------------------+
```

---

## 2. Directory Structure

```
SoC_verification/
├── Makefile                          # Master Makefile for unit, full SoC, and regression targets
├── run_regression.sh                 # Self-contained regression test runner script
├── README.md                         # Verification framework documentation (this file)
├── rtl/                              # Standalone RTL snapshot copied from source/
│   ├── components/                   # CPU execution datapath components
│   ├── debugger/                     # Core debugger, ADP control, FT1248, AHB mux
│   ├── main/                         # Top-level integration & CPU wrapper
│   └── uncore/                       # Interconnect, RAM, ROM, bridge, and all APB peripherals
├── vip/                              # Reusable Universal Verification Components (UVCs)
│   ├── ahb_lite_vip/                 # AMBA 3 AHB-Lite Master VIP (Driver, Monitor, Sequencer, Agent)
│   ├── apb_vip/                      # AMBA 3 APB Master VIP (Driver, Monitor, Sequencer, Agent)
│   ├── gpio_vip/                     # General Purpose I/O Pin VIP (Driver, Monitor, Agent)
│   └── irq_vip/                      # Interrupt Verification VIP (Monitor, Collector, Agent)
├── unit_tests/                       # Standalone Peripheral Unit Testbenches
│   ├── gpio/                         # GPIO APB + GPIO VIP + APB VIP testbench
│   ├── clint/                        # CLINT APB + IRQ VIP (Timer & SW IRQs)
│   ├── plic/                         # PLIC APB + IRQ VIP (Priorities, Claim/Complete)
│   ├── sysctrl/                      # SysCtrl APB (Reset, Vectors, Remap, SYS_ID)
│   ├── multiplier/                   # Hardware Multiplier AHB Slave unit test
│   ├── uart/                         # 16550 UART APB unit testbench
│   └── spi/                          # SPI Controller APB unit testbench
└── soc_coreless/                     # Whole Coreless SoC Verification Environment
    ├── dut/
    │   └── riscv_soc_ahb_coreless.sv # Coreless DUT wrapping uncore + multiplier + debug
    ├── tb/
    │   ├── tb_soc_coreless_top.sv    # Top-level testbench with VIP hookups
    │   ├── ahb_protocol_checker.sv   # Formal SystemVerilog Assertions (SVA)
    │   └── spi_flash_model.sv        # Behavioral SPI flash slave model
    ├── env/
    │   ├── soc_coreless_env.sv       # Top UVM environment integrating all agents
    │   ├── soc_coreless_env_pkg.sv   # Package import definitions
    │   ├── soc_ral_model.sv          # UVM RAL Register Model (SysCtrl, GPIO, Multiplier)
    │   ├── soc_scoreboard.sv         # Multi-stream scoreboard with memory shadow checking
    │   └── soc_coverage.sv           # Bus functional coverage (slaves, sizes, bursts, crosses)
    └── tests/
        ├── soc_base_test.sv          # Base test configuration and phasing
        ├── soc_reset_test.sv         # Power-on reset & telemetry validation
        ├── soc_ahb_single_rw_test.sv # Single R/W transfers to RAM, SysCtrl, Multiplier
        ├── soc_ahb_address_decode_test.sv # Comprehensive address decoding across all 11 slaves
        ├── soc_gpio_vip_test.sv      # Full GPIO VIP loopback and interrupt propagation
        ├── soc_clint_irq_test.sv     # End-to-end CLINT MTimerInt & MSwInt via AHB
        ├── soc_plic_irq_test.sv      # End-to-end Peripheral -> PLIC -> MExtInt routing & claim
        ├── soc_sysctrl_remap_test.sv # SysCtrl ROM-to-RAM remap validation
        ├── soc_concurrency_stress_test.sv # Concurrent traffic to memories, multiplier & GPIO
        ├── soc_all_suite_test.sv     # Master regression suite executing all phases
        └── soc_test_pkg.sv           # Test package compilation header
```

---

## 3. SoC Memory Map

| Slave / Peripheral | Base Address | End Address | Bus | Description |
|:---|:---:|:---:|:---:|:---|
| **Boot ROM** | `0x0000_1000` | `0x0000_1FFF` | AHB | 4 KB On-chip Boot ROM (remappable to 0x0) |
| **CLINT** | `0x0200_0000` | `0x0200_FFFF` | APB | Core Local Interruptor (MTIME, MTIMECMP, MSIP) |
| **Core Debug AHB** | `0x0B00_0000` | `0x0B00_0FFF` | AHB | Debugger memory-mapped registers |
| **PLIC** | `0x0C00_0000` | `0x0FFF_FFFF` | APB | Platform-Level Interrupt Controller (Gateway, Claim) |
| **UART 16550** | `0x1000_0000` | `0x1000_0FFF` | APB | 16550-compatible Serial Controller |
| **SPI Controller** | `0x1004_0000` | `0x1004_0FFF` | APB | SPI Flash Controller |
| **GPIO** | `0x1006_0000` | `0x1006_0FFF` | APB | 32-bit Bidirectional General-Purpose I/O |
| **SysCtrl** | `0x1008_0000` | `0x1008_0FFF` | APB | System Reset, Boot Mode, Remap & Device ID |
| **Multiplier Socket** | `0x3000_0000` | `0x30FF_FFFF` | AHB | Dedicated hardware multiply accelerator |
| **Instruction RAM** | `0x8000_0000` | `0x8000_7FFF` | AHB | 32 KB High-speed SRAM for program instructions |
| **Data RAM** | `0x8001_0000` | `0x8001_7FFF` | AHB | 32 KB High-speed SRAM for variables and stack |

---

## 4. Verification VIP Components

### 4.1 AMBA 3 AHB-Lite Master VIP (`vip/ahb_lite_vip/`)
- Fully supports AMBA 3 AHB-Lite protocol with pipelined address and data phases.
- Accurately handles slave wait-state insertion via `HREADY` sampling.
- Parametric data and address widths (32-bit and 64-bit support).
- Helper sequence methods: `write_word()`, `read_word()`, `read_check()`.

### 4.2 AMBA 3 APB Master VIP (`vip/apb_vip/`)
- Cycle-accurate APB protocol handling (`IDLE`, `SETUP`, `ACCESS` phases).
- Dedicated error tracking on `PSLVERR` and wait-state monitoring on `PREADY`.
- Helper sequence methods: `write()`, `read()`, `read_check()`.

### 4.3 General Purpose I/O VIP (`vip/gpio_vip/`)
- Bi-directional pin driving and monitoring.
- Clocking block synchronized edge driving (`drive_pattern`, `trigger_rising_edge`, `trigger_falling_edge`, `pulse_pin`).
- Independent monitor collecting `gpio_item` transactions for pin-level scoreboarding.

### 4.4 Interrupt Verification VIP (`vip/irq_vip/`)
- Real-time sampling and classification of SoC interrupt lines:
  - `MTimerInt` (CLINT machine timer interrupt)
  - `MSwInt` (CLINT machine software interrupt)
  - `MExtInt` (PLIC external machine interrupt)
  - `GPIOIntr` (GPIO edge/level interrupt)
  - `UARTIntr` (UART TX/RX interrupt)
  - `SPIIntr` (SPI transfer complete interrupt)
- Cycle-accurate transition logging and latency measurement.

---

## 5. Verification Test Suite

### 5.1 Standalone IP Unit Verification

| IP Block | Test Name | Key Verification Scenarios | Status |
|:---|:---|:---|:---:|
| **GPIO** | `gpio_unit_test` | Reset defaults, output pin driving, VIP input patterns, rising/falling edge interrupts, W1C clear. | **PASSED** |
| **CLINT** | `clint_unit_test` | Timer tick counting, `MTIMECMP` match triggering `MTimerInt`, MSIP triggering `MSwInt`. | **PASSED** |
| **PLIC** | `plic_unit_test` | Priority arbitration, threshold masking, `MExtInt` assertion, interrupt claim and complete. | **PASSED** |
| **SysCtrl** | `sysctrl_unit_test` | SYS_ID verification (`0x170950C1`), soft core reset, reset vector update, ROM remap control. | **PASSED** |
| **Multiplier** | `multiplier_unit_test` | Operand A/B loading, single-cycle 32-bit multiplication, boundary and zero multiplication. | **PASSED** |
| **UART** | `uart_unit_test` | Line status register checks (THRE/TEMT), baudrate divider configuration, character writes. | **PASSED** |
| **SPI** | `spi_unit_test` | SPI clock divider configuration, FIFO status register checks, command transmission. | **PASSED** |

### 5.2 Whole Coreless SoC Verification

| Test Name | File | Description & Assertions | Status |
|:---|:---|:---|:---:|
| `soc_reset_test` | [`soc_reset_test.sv`](soc_coreless/tests/soc_reset_test.sv) | Validates post-reset bus stability, default SYS_ID, and telemetry lines. | **PASSED** |
| `soc_ahb_single_rw_test` | [`soc_ahb_single_rw_test.sv`](soc_coreless/tests/soc_ahb_single_rw_test.sv) | Single read/write operations to IRAM, DRAM, SysCtrl, and Multiplier socket. | **PASSED** |
| `soc_ahb_address_decode_test` | [`soc_ahb_address_decode_test.sv`](soc_coreless/tests/soc_ahb_address_decode_test.sv) | Exhaustive frontdoor read/write across all 11 address-mapped SoC slaves. | **PASSED** |
| `soc_gpio_vip_test` | [`soc_gpio_vip_test.sv`](soc_coreless/tests/soc_gpio_vip_test.sv) | End-to-end GPIO VIP pin driving, AHB readback, rising-edge detection, and W1C clear. | **PASSED** |
| `soc_clint_irq_test` | [`soc_clint_irq_test.sv`](soc_coreless/tests/soc_clint_irq_test.sv) | End-to-end `MTimerInt` and `MSwInt` interrupt assertion and clearance through AHB. | **PASSED** |
| `soc_plic_irq_test` | [`soc_plic_irq_test.sv`](soc_coreless/tests/soc_plic_irq_test.sv) | Peripheral event (GPIO) routing through PLIC to `MExtInt` at SoC boundary and claim read. | **PASSED** |
| `soc_sysctrl_remap_test` | [`soc_sysctrl_remap_test.sv`](soc_coreless/tests/soc_sysctrl_remap_test.sv) | Boot ROM address space (`0x0000_0000`) dynamically remapped to IRAM via SysCtrl register. | **PASSED** |
| `soc_concurrency_stress_test` | [`soc_concurrency_stress_test.sv`](soc_coreless/tests/soc_concurrency_stress_test.sv) | Concurrent traffic streams to IRAM, DRAM, Multiplier, and asynchronous GPIO pin driving. | **PASSED** |
| `soc_all_suite_test` | [`soc_all_suite_test.sv`](soc_coreless/tests/soc_all_suite_test.sv) | Master regression test suite executing all 8 integration phases sequentially. | **PASSED** |

---

## 6. How to Run Verification

### 6.1 Prerequisites
QuestaSim 2023.4_5 (or compatible SystemVerilog simulator with UVM 1.1d/1.2 support).
```bash
module load mentor/questasim/2023.4_5
```

### 6.2 Running the Complete Automated Regression
Execute the master regression script from `SoC_verification/`:
```bash
cd SoC_verification
./run_regression.sh
```
This runs all 7 IP unit tests and all 9 Coreless SoC tests, logging output to `regression_logs/` and displaying a real-time summary table.

### 6.3 Running via Makefile
From `SoC_verification/`:
```bash
# Run all unit tests and coreless SoC tests:
make regression

# Run all 7 standalone peripheral unit tests:
make unit_all

# Run individual peripheral unit test:
make unit_gpio
make unit_clint
make unit_plic

# Run whole coreless SoC master suite:
make soc_all

# Run individual whole SoC test:
make soc_gpio_vip
make soc_plic_irq
make soc_clint_irq
make soc_remap
make soc_stress
```

### 6.4 Clean Build Artifacts
```bash
make clean
```

