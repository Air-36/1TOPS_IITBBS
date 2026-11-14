# 1TOPS RISC-V SoC

A compact, synthesizable **32-bit RISC-V System-on-Chip** built at **IIT Bhubaneswar** as the bare-metal controller for a memory-mapped hardware accelerator (originally a Convolutional Tsetlin Machine).

Inside the SoC:

- a custom **5-stage pipelined RV32I + Zicsr core** (machine mode);
- an **AMBA 3 AHB-Lite / APB** bus fabric;
- on-chip **instruction, data and boot memories**;
- standard RISC-V platform **peripherals** (CLINT, PLIC, UART, SPI, GPIO, System Control);
- a **16 MB accelerator socket**;
- a full **in-hardware debugger** that you talk to over a plain serial link. No JTAG pod is needed.

<!-- TODO: add badges / team names / licence once decided -->

---

## Contents

1. [Key features](#1-key-features)
2. [Architecture](#2-architecture)
3. [Memory map](#3-memory-map)
4. [Repository layout](#4-repository-layout)
5. [Quick start](#5-quick-start)
6. [Hardware debugger (ADP) quick reference](#6-hardware-debugger-adp-quick-reference)
7. [Boot flow](#7-boot-flow)
8. [Verification](#8-verification)
9. [FPGA prototyping](#9-fpga-prototyping)
10. [Known issues and open items](#10-known-issues-and-open-items)
11. [Documentation index](#11-documentation-index)
12. [Origins and credits](#12-origins-and-credits)

---

## 1. Key features

| Item | Value |
|---|---|
| ISA | RV32I + Zicsr, machine mode only (`misa` = `0x4000_0100`) |
| Core | In-order, single-issue, 5 stages (F, D, E, M, W), full forwarding, branches resolved in E |
| Performance | Dhrystone **0.71 DMIPS/MHz** (CPI 1.55) · CoreMark CPI 1.54 |
| Clock | 50 MHz on FPGA; 100 MHz default parameter |
| Bus | AHB-Lite with 2 masters (CPU, debugger) + APB for peripherals |
| Memories | 32 KB IRAM · 32 KB DRAM · 4 KB boot ROM (synthesises to logic) |
| Peripherals | CLINT, PLIC, UART (16550-style), SPI master (SiFive FU540-compatible), 32-bit GPIO, System Control |
| Accelerator | 16 MB AHB window at `0x3000_0000` (demo multiplier fitted) |
| Debug | ASCII Debug Protocol over UART (115200 8N1) or FT1248: halt, step, memory R/W/upload, post-mortem crash inspection |
| Boot | Boot ROM pulls programs over SPI from a Raspberry Pi Pico / Pi 4 (one or two stages) |
| FPGA | Digilent Basys 3 (proven), AMD ZCU102 (to be tested) |

---

## 2. Architecture

```text
              debugger UART / FT1248
                       |
              +--------v---------+        halt / step / reset
              | HARDWARE DEBUGGER|-----------------------------+
              |  ADP engine      |                             |
              +--------+---------+                             v
                       | M1                     +----------------------------+
                       |                        |  5-STAGE RV32I CORE        |
                       |                        |  F | D | E | M | W         |
                       |                        |  hazard unit, CSRs, traps  |
                       |                        +-------------+--------------+
                       |                                      | M0
                    +--v--------------------------------------v--+
                    |            2-to-1 AHB ARBITER              |
                    +---------------------+----------------------+
                                          | AHB-Lite
     +-----------+-----------+------------+-----------+---------------+
     v           v           v            v           v               v
 Boot ROM     IRAM 32K    DRAM 32K   Accel socket  Core-debug    AHB->APB bridge
 0x0000_1000  0x8000_0000 0x8001_0000 0x3000_0000  0x0B00_0000          |
                                                                        | APB
                     +---------+---------+---------+---------+----------+
                     v         v         v         v         v          v
                   CLINT     PLIC      UART       SPI       GPIO     SYSCTRL
```

- **Bus ownership:** the CPU owns the bus while it runs. When the core is halted or stepping, the debugger gets priority.
- **Interrupts:** the CLINT raises the timer and software interrupts. The PLIC merges the UART, GPIO and SPI interrupts into one machine external interrupt. Priority is external > software > timer.
- **Start address:** after a system reset the core starts in the boot ROM. After a debugger reset it starts in IRAM at `0x8000_0000`.

---

## 3. Memory map

| Start | End | Size | Bus | Block |
|---|---|---|---|---|
| `0x0000_1000` | `0x0000_1FFF` | 4 KB | AHB | Boot ROM (hidden when SYSCTRL remap = 1) |
| `0x0200_0000` | `0x0200_FFFF` | 64 KB | APB | CLINT: `msip` +0x0, `mtimecmp` +0x4000, `mtime` +0xBFF8 |
| `0x0B00_0000` | `0x0B00_0FFF` | 4 KB | AHB | Core post-mortem debug window |
| `0x0C00_0000` | `0x0FFF_FFFF` | 64 MB | APB | PLIC |
| `0x1000_0000` | `0x1000_0FFF` | 4 KB | APB | UART |
| `0x1004_0000` | `0x1004_0FFF` | 4 KB | APB | SPI master |
| `0x1006_0000` | `0x1006_0FFF` | 4 KB | APB | GPIO |
| `0x1008_0000` | `0x1008_0FFF` | 4 KB | APB | System Control (chip ID `0x1709_50C1` at +0x18) |
| `0x3000_0000` | `0x30FF_FFFF` | 16 MB | AHB | Accelerator socket |
| `0x8000_0000` | `0x8000_7FFF` | 32 KB | AHB | Instruction RAM |
| `0x8001_0000` | `0x8001_7FFF` | 32 KB | AHB | Data RAM (stack top `0x8001_8000`) |

Notes:

- Unmapped addresses read 0 with an OKAY response; there is no error-responding default slave.
- Peripherals decode a 4 KB window but use only a few registers at its start, so the registers repeat inside the window.

---

## 4. Repository layout

```text
1TOPS_IITBBS/
├── source/                     # Single RTL tree + in-tree verification
│   ├── components/             #   Core building blocks (ALU, decoders, hazard, CSR, trap, EBU, ...)
│   ├── main/                   #   CPU top (riscv_cpu.v) and SoC top (soc/riscv_soc_ahb.v)
│   ├── uncore/                 #   Address decoder, RAM/ROM, AHB-APB bridge, peripherals, SYSCTRL
│   ├── debugger/               #   ADP debugger, arbiter, step controller, post-mortem slave
│   │   ├── COMMANDS.md         #     Full ADP command reference
│   │   └── sw/dbg_cli.py       #     Python host CLI
│   ├── final_tests/            #   8 verification suites (core → full debugger)
│   ├── standard_core_tests/    #   riscv-arch-test, riscv-tests, CoreMark, Dhrystone, Embench, riscv-dv
│   └── README.md               #   Detailed design documentation
├── software/                   # Test programs, boot ROMs, image tools (Makefile)
│   ├── bootrom_int/            #   Internal (hard-wired) boot ROM
│   ├── bootrom_ext/            #   Second-stage boot ROM sent over SPI
│   ├── common/loader.S         #   Shared SPI loader
│   ├── pico_spi_boot/          #   Raspberry Pi Pico SPI-slave firmware
│   ├── gen_bootrom.py          #   Assembled ROM → synthesizable case table
│   └── make_image.py           #   ELF → "BOOT" SPI stream (and send to Pico)
├── fpga/                       # Basys 3 build (top, constraints, Tcl) + guides
│   └── zcu102/                 #   ZCU102 port (remote Vivado + hw_server flow)
├── SoC_verification/           # Questa UVM environment (VIPs, IP, coreless and full-core SoC tests)
├── unit_verification/          # UVM unit benches: alu, branching_unit, hazard, regfile
├── spyglass/                   # Lint / CDC / RDC project and constraints
├── schematics/                 # Vivado schematic export scripts
├── rtlvision/                  # RTLvision PRO viewing setup
├── filelist.f                  # RTL file list
├── Makefile                    # Top-level: software + test suites
└── run.sh                      # HWSTRB / bus-ownership regression
```

---

## 5. Quick start

### 5.1 Prerequisites

| Purpose | Tool |
|---|---|
| Software | GNU RISC-V cross-compiler (`riscv64-unknown-elf-` or `riscv-none-elf-`, RV32I target), Python 3 |
| Simulation | QuestaSim (UVM suites), Icarus Verilog 12, Verilator 5, Spike (golden reference) |
| FPGA | Vivado |
| Boot partner | Pico SDK (Raspberry Pi Pico) |

### 5.2 Build the software

```bash
make software          # or: make -C software
make -C software rom   # regenerate the boot ROM table (needs the RISC-V toolchain)
```

### 5.3 Run the verification suites

```bash
make test_all                     # all subsystem suites
make test_01_core_modules         # ALU, branch, immediate, subword
make test_02_pipeline_hazard      # forwarding, stalls, SVA
make test_03_cpu_core_arch        # compliance vs Spike
make test_04_bus_fabric           # AHB arbiter + APB bridge
make test_05_peripherals          # CLINT, PLIC, UART, SPI, GPIO, SYSCTRL, accelerator
make test_06_debugger             # stall, retire, ADP basics
make test_07_benchmarks           # C programs on the full SoC
make -C source/final_tests/08_debugger_verification test_all   # full debugger suite
./run.sh                          # HWSTRB / bus-ownership regression
```

### 5.4 Build the FPGA bitstream (Basys 3)

```bash
cd fpga
./run_build.sh                         # batch build
# or
vivado -mode gui -source build_fpga.tcl
```

For the ZCU102, see [`fpga/zcu102/README.md`](fpga/zcu102/README.md) (`make help`).

### 5.5 First session on the board

1. Program the bitstream and open a terminal at **115200 8N1**, line ending CR or LF.
2. Press the reset button. The board prints ` 0x50c1ab04` and the prompt `]`.
3. Load and run the factorial demo:

```text
C 0202                      # halt the core
A 80000000                  # IRAM
V 00000000
F 200                       # clear 2 KB
A 80010000
W 00000005                  # n = 5
W 00000000
A 80000000
U 4c                        # then send software/factorial.bin (76 bytes) as raw binary
C 0201                      # core reset: restarts at 0x8000_0000
C 0101
C 0102                      # run
C 0202                      # halt
A 80010004
R                           # → R 0x00000078  (5! = 120)
```

---

## 6. Hardware debugger (ADP) quick reference

Command format: one letter, an optional hex value, then Enter. Commands are case-insensitive. The number of hex digits typed sets the access size: 1–2 digits = byte, 3–4 = halfword, 5–8 = word.

| Cmd | Syntax | Action |
|---|---|---|
| `A` | `A <addr>` | Set / show the address pointer |
| `R` | `R` / `R <n>` | Read one word / `n` items, auto-increment |
| `W` | `W <val>` | Write, auto-increment |
| `V` | `V <val>` | Set reference value (for `F`, `P`) |
| `M` | `M <mask>` | Set poll mask |
| `F` | `F <n>` | Fill `n` items with `V` |
| `U` | `U <n>` | Upload `n` raw binary bytes |
| `P` | `P <t>` | Poll until `(data & M) == V` or `t` reads |
| `C` | `C 02xx` / `C 01xx` / `C 03xx` / `C` | Set / clear / overwrite control bits, or read status |
| `B` | `B [..]` | Read / set UART and FT1248 dividers |
| `D` | `D [hh]` | Read / set FT1248 divider |
| `X` / `ESC` | | Leave / re-enter command mode |

| Core action | Command |
|---|---|
| Halt / resume | `C 0202` / `C 0102` |
| Instruction step | `C 0204` then `C 0104` |
| Clock step | `C 020c` then `C 010c` |
| Core reset (restart at IRAM) | `C 0201` then `C 0101` |
| Status | `C` → `C 0x<GPI8><GPO8><param>` |

**Post-mortem window `0x0B00_0000`:**

| Offset | Contents |
|---|---|
| `+0x000` | GPRs x0–x31 |
| `+0x080` | Pipeline PCs |
| `+0x0A0` | CSRs |
| `+0x0D0` | `DBG_CTRL` (auto-halt enables, trap clear) |
| `+0x0D4` | Sticky trap cause / value / PC |
| `+0x0E0` | Link dividers |
| `+0x100` | 16-entry trace of retired PCs |

Auto-halt on trap is **off after reset**. Arm it with `A 0B0000D0` then `W 00000003`.

Full reference: [`source/debugger/COMMANDS.md`](source/debugger/COMMANDS.md).

---

## 7. Boot flow

| Reset source | Core starts at |
|---|---|
| Power-on / board reset / SYSCTRL soft core reset | Boot ROM `0x0000_1000` |
| Debugger core reset (`C 0201` / `C 0101`) | IRAM `0x8000_0000` (boot ROM never runs) |

**SPI boot**

1. After a system reset, the internal boot ROM sets the stack and configures the SPI master (mode 3, 8-bit frames, MSB first, CS0).
2. It reads one image from the boot partner (Pico / Pi 4) acting as an SPI slave, then jumps to the image's entry address.

Stream format (little-endian):

```text
"BOOT" | { addr(4) size(4) data(size) }* | entry(4) 0x00000000
```

| Mode | Stream contents | What happens |
|---|---|---|
| 0 | `[test image]` | The internal ROM loads the program and jumps to it |
| 1 | `[ext boot ROM][test image]` | The second-stage ROM runs from `0x8000_7C00` and loads the test image |

Errors are written to `0x8001_7FFC`, then the loader loops:

| Code | Meaning |
|---|---|
| `0xE1` | Bad magic (stream did not start with "BOOT") |
| `0xE2` | Chunk outside IRAM/DRAM |

Build the stream with `software/make_image.py`. Every boot is "reload the stream into the partner, then reset the SoC".

> ⚠️ The ROM table in `source/uncore/rom_ahb.sv` still holds the older dual-mode teammate ROM. Run `make -C software rom` to install the SPI loader.

---

## 8. Verification

| Layer | Where | Result |
|---|---|---|
| Core units (exhaustive) | `source/final_tests/01_core_modules` | Pass |
| Pipeline hazard stress + SVA | `02_pipeline_hazard_stress` | Pass |
| Architectural compliance vs Spike | `03_cpu_core_arch` | Pass |
| Bus fabric (CRV + protocol checkers) | `04_bus_fabric` | Pass |
| Peripherals, SYSCTRL, boot | `05_peripherals` | Pass |
| Debugger features | `06_debugger_subsystem` | Pass |
| C benchmarks on full SoC | `07_soc_system_benchmarks` | Pass |
| Full debugger (block + SoC) | `08_debugger_verification` | Block 524 pass / 3 XFAIL · SoC 75 pass / 9 XFAIL |
| Industry suites | `source/standard_core_tests` | arch-test, riscv-tests pass; CoreMark, Dhrystone, Embench measured |
| UVM (VIPs, RAL, scoreboard) | `SoC_verification/`, `unit_verification/` | All listed tests pass |
| Static (lint, CDC, RDC) | `spyglass/` | Reports archived |

XFAIL = a test that reproduces a known, tracked bug (see §10). When the bug is fixed the test reports XPASS and the tag is removed.

---

## 9. FPGA prototyping

| Board | Status | Notes |
|---|---|---|
| **Digilent Basys 3** (Artix-7 35T) | ✅ Running | 100 MHz → MMCM → 50 MHz; SW0 = debugger link (UART/FT1248); SW1 = boot strap; FT1248 on PMOD JB; SPI boot on PMOD JC |
| **AMD ZCU102** (Zynq US+) | 🟡 Sim-verified (17/17), board bring-up pending | PL-only port; 125 MHz → 50 MHz; debugger UART on CP2108 ch. 2; built remotely, programmed via `hw_server :3121` |

Pin assignments: `fpga/constrs/basys3.xdc` and `fpga/zcu102/constrs/`.

Further guides:

- [`fpga/README.md`](fpga/README.md)
- [`fpga/PERIPHERAL_VERIFICATION_GUIDE.md`](fpga/PERIPHERAL_VERIFICATION_GUIDE.md)
- [`fpga/STEP_AND_CLOCK_DIV_VERIFICATION_GUIDE.md`](fpga/STEP_AND_CLOCK_DIV_VERIFICATION_GUIDE.md)

---

## 10. Known issues and open items

| Area | Item |
|---|---|
| Boot ROM | ROM table not yet regenerated from the SPI loader |
| SPI | Polling `rxdata` can lose a byte (read pops the FIFO but reports empty). Wait on `ip[1]` first; an RTL fix is pending |
| Boot stream | No CRC/checksum |
| UART | The SoC builds a register-only model (`USE_REAL_UART = 0`): no real TX/RX on hardware |
| SYSCTRL | Reset-vector, clock-gating and peripheral-reset outputs are not connected |
| PLIC | No gateway; claim/complete writes have no effect |
| Bus | No default slave: unmapped accesses return OKAY + 0 (**A3**) |
| Core | **N2** unknown opcodes not trapped as illegal · **N3** AHB request changes during a wait state · **N8** interrupt return resume point · **N9** misaligned jump not trapped |
| Debugger docs | **C11** small differences between `COMMANDS.md` and the RTL |
| Verification | UVM environment uses a drifted RTL snapshot; re-sync and re-run |
| Hardware | ZCU102 and Raspberry Pi 4 boot partner not yet brought up |

---

## 11. Documentation index

| Document | Content |
|---|---|
| [`source/README.md`](source/README.md) | Detailed architecture, pipeline, memory map, debugger walkthrough |
| [`source/debugger/COMMANDS.md`](source/debugger/COMMANDS.md) | Complete ADP command reference and post-mortem register map |
| [`source/debugger/DEBUGGER_WIRING_GUIDE.md`](source/debugger/DEBUGGER_WIRING_GUIDE.md) | Debugger integration and wiring |
| [`source/final_tests/README.md`](source/final_tests/README.md) | Verification suite overview |
| [`SoC_verification/README.md`](SoC_verification/README.md) | UVM environment |
| [`software/README.md`](software/README.md) | Programs, boot ROMs, image tools |
| [`fpga/README.md`](fpga/README.md) · [`fpga/zcu102/README.md`](fpga/zcu102/README.md) | FPGA builds and bring-up |

---

## 12. Origins and credits

| Part | Origin |
|---|---|
| Processor core | Custom 5-stage RV32I design written for this project |
| Uncore (CLINT, PLIC, UART, SPI, GPIO, RAM/ROM wrappers, AHB-APB bridge) | Derived from the open-source [CORE-V-Wally](https://github.com/openhwgroup/cvw) uncore, simplified and adapted |
| Debugger front-end (ADP engine, UART and FT1248 links) | Based on SoC Labs **SoCDebug** (Arm Academic Access licence), extended with core stepping, auto-halt and the post-mortem slave |
| System Control, accelerator socket, boot flow, FPGA tops, verification suites | Written for this project |

<!-- TODO: team members, supervisor, licence, citation -->

**Institute:** Indian Institute of Technology Bhubaneswar
