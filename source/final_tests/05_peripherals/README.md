# Subsystem 05: Peripherals & Accelerator IP Socket Verification

This subsystem contains dedicated self-checking verification tests for all SoC uncore peripherals and accelerator IP socket integrated via the AMBA AHB/APB interconnect.

---

## 1. Subsystem Architecture Overview

The peripheral subsystem connects to the CPU core via the Uncore subsystem and contains:
1. **Accelerator IP Socket (Part of Uncore) ([multiplier_ahb.v](file:///home/23EC01043/Desktop/1TOPS/1TOPS_IITBBS/source/main/soc/multiplier_ahb.v))**:
   - Memory space: `0x3000_0000 - 0x30FF_FFFF` (1TOPS SoC `EXT_MEM` space).
   - High-performance 32-bit hardware multiplication engine with memory-mapped operand registers:
     - `0x00`: Operand A (32-bit R/W)
     - `0x04`: Operand B (32-bit R/W)
     - `0x08`: Product Output (32-bit Read-Only: `Operand A * Operand B`)
     - `0x0C`: Testbench Console Character Output (Write-Only)
2. **GPIO Peripheral ([gpio_apb.sv](file:///home/23EC01043/Desktop/1TOPS/1TOPS_IITBBS/source/uncore/gpio_apb.sv))**:
   - Base Address: `0x1006_0000`.
   - 32 general-purpose I/O pins with direction control (`GPIOEN`), output driver (`GPIOOUT`), input sampling (`GPIOIN`), and interrupt generation.
3. **16550 UART Peripheral ([uart_apb.sv](file:///home/23EC01043/Desktop/1TOPS/1TOPS_IITBBS/source/uncore/uart_apb.sv))**:
   - Base Address: `0x1000_0000`.
   - Full 16550-compatible UART with Transmit/Receive Holding Registers (`RBR`/`THR`), Interrupt Enable Register (`IER`), FIFO Control (`FCR`), Line Control (`LCR`), and Line Status (`LSR`).
4. **CLINT (Core Local Interruptor) ([clint_apb.sv](file:///home/23EC01043/Desktop/1TOPS/1TOPS_IITBBS/source/uncore/clint_apb.sv))**:
   - Base Address: `0x0200_0000`.
   - Implements RISC-V Privileged Architecture `mtime` (64-bit real-time counter) and `mtimecmp` (timer comparator for `MTIP` timer interrupt generation).
5. **PLIC (Platform-Level Interrupt Controller) ([plic_apb.sv](file:///home/23EC01043/Desktop/1TOPS/1TOPS_IITBBS/source/uncore/plic_apb.sv))**:
   - Base Address: `0x0C00_0000`.
   - Routes, prioritizes, and arbitrates external peripheral interrupts (UART, GPIO, SPI) to the CPU core's `MEIP` external interrupt input with priority thresholds and claim/complete handshaking.
6. **System Control Block ([sysctrl_apb.sv](file:///home/23EC01043/Desktop/1TOPS/1TOPS_IITBBS/source/uncore/sysctrl_apb.sv)) & Boot ROM ([rom_ahb.sv](file:///home/23EC01043/Desktop/1TOPS/1TOPS_IITBBS/source/uncore/rom_ahb.sv))**:
   - Base Address: `0x1008_0000` (APB Slot 5).
   - Implements synchronous reset control, boot mode pin strap sampling, programmable reset vector (`0x1008_0004`), address remapping (`0x1008_000C`), peripheral clock gating (`0x1008_0010`), and scratchpad diagnostics (`0x1008_0014`).
   - Drives dual-mode cold booting: Mode 0 (Internal Boot ROM self-test and `main()`) and Mode 1 (External SPI Flash loader streaming into IMEM at `0x8000_0000`).

---

## 2. Test Suite Details

| Test Target | Target Peripheral | Test Source | Verification Scope |
|-------------|-------------------|-------------|--------------------|
| `test_multiplier` | Accelerator IP Socket | `tb/tb_multiplier_ahb.sv` | Unit verification: Small positive, large values, zero/identity, signed 2's complement, and 50 constrained-random multiplications (165 assertion checks). |
| `test_gpio` | APB GPIO Subsystem | `src/1TOPS_SOC-gpio-01.S` | Full SoC execution: Direction register toggling, pin mask generation, and readback against input stimulus `0xA5A55A5A`. |
| `test_uart` | APB 16550 UART | `src/1TOPS_SOC-uart-01.S` | Full SoC execution: Divisor latch programming, loopback character transmit, FIFO status check, and receive buffer drain. |
| `test_clint` | APB CLINT Timer | `src/1TOPS_SOC-clint-01.S` | Full SoC execution: `mtime` increments, timer interrupt arming via `mtimecmp`, and trap handler dispatch. |
| `test_plic` | APB PLIC Interrupts | `src/1TOPS_SOC-plic-01.S` | Full SoC execution: Priority configuration, interrupt enablement, priority threshold masking, and atomic claim/complete cycle. |
| `test_boot_sysctrl` | System Control & Dual-Mode Boot | `tb/tb_sysctrl_boot.sv` | Full SoC execution: Verifies strap latching, internal ROM execution and reaching main(), external SPI Flash loading into IMEM, and ROM remap. |

---

## 3. How to Run

From this directory:

```bash
# Run all peripheral and accelerator tests
make test_all

# Run individual peripheral tests
make test_multiplier
make test_gpio
make test_uart
make test_clint
make test_plic
make test_boot_sysctrl

# Clean build and memory artifacts
make clean
```

All test runs compile libraries and assembly vectors fresh before simulation.
