# 1TOPS SoC: Technical Overview and Reference

**Scope:** a complete description of the 1TOPS RISC-V System-on-Chip: what it is, how it is organised, how every major block works, how it boots, how it is verified, and how it is brought up on FPGA boards.

**Intended use:** source material for reports and presentations. It is deliberately exhaustive; trim what you need. It describes behaviour and structure rather than code, so it can be read without access to the repository.

**Status date:** 13 November 2026

---

## Contents

1. Executive summary
2. Project context and origins
3. System architecture (top-level view)
4. Memory map and address decoding
5. The processor core
6. Bus fabric
7. On-chip memories
8. Peripherals
9. The accelerator socket
10. The hardware debugger
11. Clocks and resets
12. The boot flow
13. SPI boot partner devices: Raspberry Pi Pico and Raspberry Pi 4
14. Software and tools
15. Verification
16. FPGA prototyping and bring-up
17. End-to-end workflow: server, lab and board
18. Known issues, limitations and open items
19. Glossary
20. Quick-reference appendix

---

## 1. Executive summary

**What it is.** The 1TOPS SoC is a compact, synthesizable 32-bit RISC-V System-on-Chip. It acts as the bare-metal **controller for a hardware accelerator**, originally a Convolutional Tsetlin Machine accelerator. Around a custom 5-stage pipelined RV32I processor core it adds:
- an AMBA bus fabric (AHB-Lite with an APB peripheral bus);
- on-chip instruction and data memories;
- a boot ROM;
- a set of standard RISC-V platform peripherals (timer, interrupt controller, UART, SPI, GPIO, system control);
- a 16 MB memory-mapped **accelerator socket**;
- a full **in-hardware debugger**, reachable over a serial link with no JTAG pod.

**Key characteristics**

| Item | Value |
|---|---|
| Instruction set | RV32I base integer ISA + Zicsr (control and status registers), machine mode only |
| Core | Custom in-order 5-stage pipeline (Fetch, Decode, Execute, Memory, Writeback) with forwarding |
| Measured efficiency | CPI ≈ 1.54–1.55; Dhrystone 0.71 DMIPS/MHz (core-only simulation with single-cycle memory) |
| Clock | 50 MHz on FPGA (both boards); designed with a 100 MHz default parameter |
| Bus | AMBA 3 AHB-Lite (two masters: CPU and debugger) + AMBA 3 APB for peripherals |
| Memories | 32 KB instruction RAM, 32 KB data RAM, 4 KB boot ROM |
| Peripherals | CLINT (timer and software interrupts), PLIC (external interrupts), UART, SPI master, 32-bit GPIO, System Control block |
| Accelerator socket | 16 MB AHB aperture at 0x3000_0000 (a demonstration multiplier is fitted today) |
| Debug | Serial "ASCII Debug Protocol" debugger: halt, single-step, memory read/write/upload, register and trace inspection, auto-halt on crash |
| Boot | Boot ROM loads programs over SPI from an external device (Pico / Raspberry Pi 4) in one or two stages |
| FPGA platforms | Digilent Basys 3 (Artix-7), AMD ZCU102 (Zynq UltraScale+) |
| Verification | Unit, pipeline-stress, ISA-compliance, bus, peripheral, debugger, system-benchmark and UVM suites, plus Spyglass static checks |

**Current state (short)**
- **Verified:** the SoC RTL is verified extensively in simulation and runs on the Basys 3 board (debugger-driven program loading and execution).
- **Implemented and verified in simulation:**
  - the SPI boot flow;
  - the ZCU102 FPGA build;
  - the Raspberry Pi 4 SPI-boot partner.

  These still need bring-up on real hardware (section 18).

---

## 2. Project context and origins

### 2.1 Purpose
The SoC is the *control processor* for an accelerator. The accelerator does the heavy computation; the SoC:
- loads and runs bare-metal firmware;
- moves data and configuration to and from the accelerator through its memory-mapped socket;
- reads results back;
- talks to the outside world (UART, SPI, GPIO);
- provides the debug and bring-up infrastructure needed to develop all of this.

### 2.2 Lineage of the design
| Part | Origin |
|---|---|
| Processor core | A custom 5-stage pipelined RV32I implementation written for this project, with an AHB-Lite master interface and debug hooks |
| Uncore peripherals and memories (timer, interrupt controller, UART, SPI, GPIO, RAM/ROM wrappers, AHB-to-APB bridge) | Derived from the open-source **CORE-V-Wally** RISC-V project's uncore (the "cvw" repository), simplified and adapted |
| Hardware debugger front-end (ASCII Debug Protocol engine, UART and FT1248 links) | Based on **SoC Labs "SoCDebug"** (commissioned on behalf of SoC Labs under the Arm Academic Access licence), extended with core stepping, auto-halt and a post-mortem inspection slave |
| System Control block, accelerator socket, boot ROM flow, FPGA tops, verification suites | Written for this project |

### 2.3 Repository history (for context)
- **Phase 1 (`cvw`):** the work started inside a fork of CORE-V-Wally (`cvw` repository, `1tops_soc/` subfolder), which held several drifting copies of the RTL.
- **Phase 2 (`1TOPS_IITBBS`):** it moved to the current, cleaned repository, with a single RTL tree.

The SPI boot flow was developed in phase 1 and then merged and adapted (new memory map, new reset scheme, synthesizable boot ROM). Change logs for both phases are kept in the repository (`changes_s1.md`, `changes_s2.md`).

---

## 3. System architecture (top-level view)

### 3.1 Block diagram

```
                         External pins / board I/O
   clock, reset, boot-mode strap, debugger UART / FT1248, SPI, UART, GPIO, status LEDs
          |                    |                                   |
          v                    v                                   |
  +---------------+   +----------------------------+               |
  | Clock & reset |   |  HARDWARE DEBUGGER         |               |
  | (system reset,|   |  - UART or FT1248 link     |               |
  |  core reset)  |   |  - ASCII Debug Protocol    |               |
  +-------+-------+   |  - bus master (master 1)   |               |
          |           |  - core step controller    |               |
          |           +------+---------------+-----+               |
          |       halt/step  |               | debugger bus        |
          v                  v               v                     |
  +----------------------------------+   +---------------------+   |
  | 5-STAGE RV32I PROCESSOR CORE     |   |                     |   |
  | Fetch | Decode | Execute |       |   |                     |   |
  | Memory | Writeback               |   |                     |   |
  | + hazard unit, CSRs, traps       |   |                     |   |
  | bus master (master 0) -----------+-->|  2-to-1 AHB ARBITER |   |
  +----------------------------------+   +----------+----------+   |
                                                    | shared AHB-Lite bus
       +----------------+----------------+----------+------+--------------+
       v                v                v                 v              v
  +---------+    +------------+   +------------+   +-------------+  +--------------+
  |Boot ROM |    |Instruction |   | Data RAM   |   | Accelerator |  | Core debug   |
  | 4 KB    |    |RAM 32 KB   |   | 32 KB      |   | socket 16 MB|  | (post-mortem)|
  +---------+    +------------+   +------------+   +-------------+  +--------------+
                                                    |
                                          +---------v---------+
                                          | AHB-to-APB bridge |
                                          +---------+---------+
                                                    | APB peripheral bus
     +-----------+-----------+-----------+----------+----------+------------+
     v           v           v           v                     v            v
  +------+   +------+    +------+    +------+              +------+    +---------+
  |CLINT |   | PLIC |    | UART |    | SPI  |              | GPIO |    | SYSCTRL |
  |timer |   |ext.  |    |      |    |master|              |      |    | boot,   |
  |irqs  |   |irqs  |    |      |    |      |              |      |    | resets  |
  +--+---+   +--+---+    +------+    +------+              +------+    +---------+
     |          |   interrupts back to the core
     +----------+------------------------------------------------------> core
```

### 3.2 How the pieces relate
- **Two bus masters share one bus.**
  - The **CPU core** (master 0) issues every instruction fetch and every data load/store on a single AHB-Lite port.
  - The **hardware debugger** (master 1) can read and write anything on the bus: memories, peripherals, the accelerator, the core-debug registers.
  - A small **arbiter** decides who drives the bus. The debugger wins when the core is halted or being single-stepped; otherwise the CPU has the bus.
- **Slaves:**
  - The memories, the accelerator socket and the core-debug block sit directly on the AHB bus.
  - Slower peripherals sit behind an **AHB-to-APB bridge** on the simpler APB bus.
- **Interrupts:**
  - The timer block (CLINT) produces timer and software interrupts.
  - The interrupt controller (PLIC) gathers peripheral interrupts (UART, GPIO, SPI) into one external interrupt.
  - All three go to the core.
- **Debug control:** the debugger can freeze the whole pipeline, step one instruction or one clock, reset the core, and read the core's internal state through a dedicated read-only window.
- **Boot:**
  - After a power-on or board reset the core starts in the boot ROM, which loads the real program into RAM over SPI and jumps to it.
  - A reset issued by the debugger instead restarts the core directly in RAM, so debugger-driven testing never runs the boot ROM.

### 3.3 Hierarchy of the design (top to bottom)
- **FPGA board top:** clock generation, board pins, LEDs, board-specific glue (one per board).
  - **SoC top:** the complete chip. It contains:
    - the hardware debugger (link front-ends, protocol engine, bus master);
    - the core step controller;
    - the 2-to-1 AHB arbiter and the debugger's byte-strobe generation;
    - the processor core: datapath, controller/decoders, hazard unit, register file, CSRs, trap unit, external bus unit;
    - the **uncore**: address decoder, instruction and data RAMs, boot ROM, AHB-to-APB bridge, CLINT, PLIC, UART, SPI, GPIO, System Control;
    - the core post-mortem debug slave;
    - the accelerator socket (currently the multiplier).

---

## 4. Memory map and address decoding

### 4.1 Memory map

| Start | End | Size | Bus | Block | Purpose |
|---|---|---|---|---|---|
| 0x0000_1000 | 0x0000_1FFF | 4 KB | AHB | Boot ROM | First code executed after a system reset |
| 0x0200_0000 | 0x0200_FFFF | 64 KB | APB | CLINT | Machine timer (mtime / mtimecmp) and software interrupt |
| 0x0B00_0000 | 0x0B00_0FFF | 4 KB | AHB | Core debug slave | Read-only window into the core's registers, PCs, CSRs, trace; debugger clock dividers |
| 0x0C00_0000 | 0x0FFF_FFFF | 64 MB | APB | PLIC | Platform-level interrupt controller |
| 0x1000_0000 | 0x1000_0FFF | 4 KB window | APB | UART | Application serial port (16550-style registers) |
| 0x1004_0000 | 0x1004_0FFF | 4 KB | APB | SPI master | SiFive-style SPI controller (boot channel) |
| 0x1006_0000 | 0x1006_0FFF | 4 KB window | APB | GPIO | 32-bit general-purpose I/O |
| 0x1008_0000 | 0x1008_0FFF | 4 KB window | APB | System Control | Boot strap, resets, remap, scratchpad, chip ID |
| 0x3000_0000 | 0x30FF_FFFF | 16 MB | AHB | Accelerator socket | Accelerator registers and buffers |
| 0x8000_0000 | 0x8000_7FFF | 32 KB | AHB | Instruction RAM | Program code |
| 0x8001_0000 | 0x8001_7FFF | 32 KB | AHB | Data RAM | Data, heap, stack (stack top 0x8001_8000) |

Notes:
- The two RAMs are **separate windows with a gap between them**: 0x8000_8000–0x8000_FFFF is unmapped. Earlier versions of the design used 8 KB + 8 KB at 0x8000_0000 and 0x8000_2000.
- The UART, GPIO and System Control blocks decode a 4 KB window but use only a few registers at its start.

### 4.2 How decoding works
- **Two-phase timing.** An AHB transfer has an address phase and a following data phase. The decoder compares the address with each window during the address phase and registers the result. In the data phase it uses that registered result to choose which slave's read data and ready/response signals go back to the master. This lets one transfer's data phase overlap the next transfer's address phase, as AHB requires.
- **APB peripherals** are all reached through one AHB slave, the AHB-to-APB bridge. The bridge has one select line per peripheral.
- **Remap.** When the System Control block's remap bit is set, the boot ROM window disappears and addresses 0x0000_0000–0x0000_7FFF become an alias of the instruction RAM, so code can run from address zero. Remap is off after reset.
- **Unmapped addresses** return zero with an "OK" response; there is no error-responding default slave. This is a known open item (section 18).

---

## 5. The processor core

### 5.1 Overview
The core is an in-order, single-issue, 5-stage pipelined implementation of **RV32I + Zicsr**, machine mode only. It has no compressed instructions, no hardware multiply/divide, no floating point, no caches, no branch predictor and no MMU. That keeps it small and easy to verify; heavy computation is the accelerator's job.

### 5.2 Pipeline stages

| Stage | What happens |
|---|---|
| **Fetch (F)** | Holds the program counter. Requests the next instruction over the bus and computes PC + 4. The next PC is chosen from: PC + 4, a branch/jump target, a register-based jump target, the trap vector, the trap-return address, or the post-fence address. |
| **Decode (D)** | Decodes the instruction (main decoder, ALU decoder, privileged-instruction decoder), reads two source registers from the 32×32-bit register file, and builds the sign-extended immediate (I, S, B, U, J formats). Illegal instructions are flagged here. |
| **Execute (E)** | Arithmetic/logic unit (add, subtract, shifts, compares, logic ops). Branch condition evaluation and target calculation. Operand forwarding muxes pick the most recent value of each source register. **Branches and jumps are resolved here.** |
| **Memory (M)** | Load/store unit: builds byte/halfword/word accesses with the correct byte strobes and sign/zero extension. CSR reads and writes and trap handling also happen here, so traps are precise. |
| **Writeback (W)** | Selects the result (ALU, load data, PC + 4, immediate, CSR value) and writes it to the register file. Signals "instruction retired" (used by the debugger's instruction stepping and the retired-instruction counter). |

### 5.3 Hazard handling
- **Data forwarding:** results waiting in the Memory and Writeback stages are forwarded to the Execute stage's inputs, so dependent instructions normally run back to back.
- **Load-use stall:** if an instruction needs the result of the load just before it, Fetch and Decode stall one cycle and a bubble enters Execute.
- **Control hazards:** branches and jumps resolve in Execute. When the PC must change (taken branch, jump, trap, trap return, fence.i), the instructions fetched behind it in Decode and Execute are flushed. There is no prediction: effectively "predict not-taken", with a taken branch costing two cycles.
- **Bus wait states:**
  - If a data access must wait, the **whole pipeline** stalls.
  - If an instruction fetch must wait, only the front of the pipeline stalls.
- **External freeze:** the debugger's step controller can stall every stage at once. The core is frozen with all state preserved, so it can be inspected and resumed. Flushes are suppressed while frozen.

### 5.4 Memory interface (External Bus Unit)
- **One AHB-Lite master port shared by fetch and load/store.** The instruction-fetch unit and the load/store unit each produce bus requests; the External Bus Unit merges them onto the single port.
- **Data accesses have priority.** A pre-empted instruction fetch is saved and replayed afterwards. Ready signals go back only to the unit that owns the current data phase.
- **Why CPI is about 1.5 even with single-cycle memory:** every instruction is fetched over the same bus that loads and stores use.

### 5.5 Privileged architecture: CSRs, traps and interrupts
- **CSRs (machine mode):**
  - status, interrupt-enable and interrupt-pending registers;
  - trap vector base (direct or vectored mode);
  - trap return address, trap cause, trap value, scratch;
  - counter-enable and counter-inhibit;
  - read-only vendor/architecture/implementation/hart IDs and ISA register.
- **Counters:** 64-bit cycle and retired-instruction counters, readable as the user counters and as the machine counters. The "time" CSR reads the CLINT's real-time counter.
- **Exceptions:** environment call, breakpoint, illegal instruction.
- **Interrupts:** machine external (from the PLIC), machine software and machine timer (both from the CLINT). Priority: external > software > timer.
- **Trap behaviour:**
  - Traps are taken in the Memory stage, so they are precise: older instructions complete, younger ones are flushed.
  - The return PC and cause are saved, interrupts are globally disabled, and execution jumps to the trap vector (vectored mode adds 4 × cause for interrupts).
  - Trap return restores the saved state.
- **WFI** (wait for interrupt) is executed as a no-op.
- **fence.i** flushes the pipeline so newly written code is fetched.

### 5.6 Debug hooks built into the core
- **External stall input:** whole-pipeline freeze, used for halt and stepping.
- **"Instruction retired" pulse**, used for exact one-instruction stepping.
- **A second, non-intrusive read port on the register file:** the debugger can read any register while the program runs, without disturbing it.
- **Exported internal state:**
  - the program counters of all five stages;
  - the instruction in the Memory stage;
  - the current trap cause and value;
  - all key CSRs and both counters;
  - stall and flush flags.

  The core post-mortem debug slave makes this readable over the bus (section 10.5).

### 5.7 Boot address selection
- **System reset** (power-on, board reset button, or the System Control block's software reset): the first instruction is fetched from the boot ROM at 0x0000_1000.
- **Reset from the debugger:** the first fetch is from the instruction RAM at 0x8000_0000.

This keeps the debugger's load-and-run testing flow completely separate from the boot flow. The selection uses a constant reset value plus a one-cycle "boot address" override, which suits ASIC synthesis (no flip-flop with a signal-dependent reset value). A flag outside the core's reset domain remembers which source caused the last reset.

### 5.8 Performance (recorded results)
Measured in core-only simulation, with the core connected straight to single-cycle RAM:

| Benchmark | Result |
|---|---|
| Dhrystone 2.1 (100 runs) | CPI 1.55; **0.71 DMIPS/MHz**; 35 DMIPS at 50 MHz |
| EEMBC CoreMark (1 iteration) | CPI 1.54; about 204,641 cycles per iteration |

---

## 6. Bus fabric

### 6.1 AHB-Lite
All high-speed traffic uses AMBA 3 AHB-Lite: 32-bit address and data, pipelined address/data phases, single transfers, byte/halfword/word sizes with byte-lane write strobes, and wait states signalled by the slave's ready output.

### 6.2 Two-master arbiter
- **Inputs:** the CPU's bus port and the debugger's bus port.
- **Grant rule:** while the core is running, the CPU owns the bus. While the core is halted or being stepped, the debugger has priority and its transfers go straight through. If both request in the same cycle, the debugger wins.
- **Data-phase tracking:** because AHB data follows its address one phase later, the arbiter registers which master was granted the address phase. Write data, byte strobes and the returned read data/ready/response are then routed to and from the correct master.
- **Byte strobes for the debugger:** the debugger issues transfers by size and address. The SoC turns these into the correct byte-lane strobes, aligned to the data phase, so the debugger's byte-wise uploads never corrupt neighbouring bytes. A bug in this muxing was fixed during development and is covered by a dedicated regression.

### 6.3 AHB-to-APB bridge
- Turns one AHB transfer into an APB transfer: a **setup** cycle, then an **access** cycle. The AHB side is held waiting until the APB access completes, and the peripheral can add further wait states.
- Has one select line per APB peripheral (six: CLINT, PLIC, UART, SPI, GPIO, System Control) and multiplexes their read data back.
- **Observed subtlety:** the bridge keeps the peripheral selected through the access cycle's closing clock edge. A peripheral that treats "a read happened" as a side effect, such as popping a FIFO, must take care which edge it uses. This caused the SPI receive race described in sections 8.4 and 18.

---

## 7. On-chip memories

### 7.1 Instruction RAM and data RAM
- **Sizes:** 32 KB each, at 0x8000_0000 (instructions) and 0x8001_0000 (data).
- **Built from four byte-wide arrays:** each 32-bit word is stored as four independent byte lanes, so byte and halfword writes only touch the lanes that change. This also lets FPGA tools map the memories onto block RAM rather than logic.
- **Timing:**
  - Reads are synchronous; data is returned in the AHB data phase.
  - A read immediately after a write to the same memory costs one wait state (single-ported memory).
  - An optional extra-latency parameter is used in some verification runs.
- **Preload:** the RAMs can be preloaded from files in simulation. On hardware they start empty (zero on FPGA) and are loaded by the boot ROM or the debugger.

### 7.2 Boot ROM
- **Location and size:** 4 KB (1,024 words) at 0x0000_1000.
- **Built from logic, not memory:** the contents are a constant table that synthesis turns into gates. That works for both an ASIC (standard cells) and an FPGA, with no memory-initialisation file needed at build time.
- **Generated from the boot program:** the table is produced by a script from the compiled boot program, and the same script writes a matching hex file for simulation. Changing the ROM means rebuilding the boot program and regenerating the table, never hand-editing.
- **Timing:** single-cycle, zero-wait response with a registered output.

---

## 8. Peripherals

All peripherals sit on the APB bus behind the bridge and use 32-bit registers.

### 8.1 CLINT: core-local interruptor (0x0200_0000)
- A 64-bit **real-time counter (mtime)** that advances once per SoC clock (50 million counts per second at 50 MHz). It can also be written, for example to test the carry between its 32-bit halves.
- A 64-bit **compare register (mtimecmp)**: the machine timer interrupt is raised while mtime ≥ mtimecmp.
- A **software interrupt bit (msip)**: writing 1 raises the machine software interrupt (used for inter-processor or test interrupts).
- Standard RISC-V register offsets: msip at +0x0, mtimecmp at +0x4000, mtime at +0xBFF8.

### 8.2 PLIC: platform-level interrupt controller (0x0C00_0000)
- Collects peripheral interrupt sources: UART (source 1), GPIO (2), SPI (3), and a reserved source 4 (an SD-card controller slot, unused).
- Per-source priority, enable and threshold. The combined result is the machine external interrupt to the core.
- **Claim/complete handshake:** software reads the claim register to learn which source is interrupting, services it, then writes the same ID back to complete it.

### 8.3 UART: application serial port (0x1000_0000)
- Programmed like a standard 16550: data, interrupt-enable, interrupt-ID/FIFO-control, line-control (with divisor latch), modem-control, line-status, modem-status and scratch registers.
- **Important: the SoC currently builds a lightweight register model, not the full serial engine.**
  - The repository also contains a full 16550 UART core (baud generator, transmit/receive serializers, 16-byte FIFOs), but the SoC is configured to use the simplified model.
  - The simplified model reports "always ready to transmit" and records written characters (printed to the console in simulation).
  - **It does not serialise data onto the transmit pin and does not receive.** So program output over this UART is visible in simulation, not on hardware. Selecting the full core is a one-parameter change, not yet made (section 18).

### 8.4 SPI master (0x1004_0000)
- **Register-compatible with the SiFive FU540 SPI controller.**
- **Registers:**
  - clock divider;
  - clock mode (polarity/phase);
  - chip-select ID, default levels and mode;
  - two delay registers (CS-to-clock, clock-to-CS, inter-transfer gaps);
  - frame format (length, bit order);
  - transmit data and receive data;
  - transmit/receive watermarks;
  - interrupt enable and pending.
- **Clocking:** SPI clock = system clock / (2 × (divider + 1)); the divider has 12 bits. At 50 MHz that is about 6.1 kHz to 25 MHz. The boot loader uses **250 kHz**.
- **Four chip-select lines.** CS modes:
  - **AUTO:** asserted per frame;
  - **HOLD:** stays asserted after the first frame until the mode changes; used by the boot loader to keep CS low for a whole image;
  - **OFF:** software-controlled default level.
- **FIFOs:** 8-entry transmit and receive. Writing the transmit register queues a byte and starts the transfer automatically; one byte is received for every byte sent.
- **Status:** transmit-full and receive-empty are reported in bit 31 of the transmit-data and receive-data registers.
- **Receive race (found during this work):** reading the receive-data register can remove a byte from the FIFO while reporting "empty", if the byte arrives exactly between the read's two APB clock edges. The boot loader therefore waits on the receive-watermark interrupt-pending bit, which has no side effect, and only then reads the data once. An RTL fix is recommended so that other software cannot fall into the same trap (section 18).

### 8.5 GPIO (0x1006_0000)
- **Registers:** 32 pins with an input-enable mask, output-enable mask and output value.
- **Interrupts:** per-pin interrupts on rising edge, falling edge, high level and low level, each with its own enable and sticky pending register; pending bits are cleared by writing 1.
- On the FPGA boards only a few GPIO inputs are wired to board resources (or none).
- **Note:** the design README describes an "XOR polarity inversion" register. The GPIO block in the current source tree does not implement one, so the README needs correcting (section 18).

### 8.6 System Control block, SYSCTRL (0x1008_0000)

| Register | Function |
|---|---|
| Reset control | Software-controlled **core reset** and peripheral reset bits; sticky "power-on reset happened" and "debugger reset happened" flags (cleared by writing 1) |
| Reset vector | A programmable reset address (default 0x0000_1000). Present as a register but **not yet connected to the core**: the core's reset address is fixed by design parameters (section 5.7) |
| Boot status | The **boot-mode strap** latched at reset, plus the live pin level |
| Remap control | Remaps addresses 0x0000_0000–0x0000_7FFF to the instruction RAM (and hides the boot ROM) |
| Clock control | An 8-bit peripheral clock-gating mask (register present; not yet connected to clock gates) |
| Scratchpad | A free 32-bit register for firmware/debugger handshakes |
| System ID | Read-only chip identifier 0x1709_50C1 |

- **Internal reset sequencer:** after reset is released, a two-stage synchroniser plus a 16-cycle hold counter. The boot-mode strap is sampled during this hold window.
- **About the boot-mode strap:** in the current SPI boot flow the boot ROM does **not** read it. The boot mode is defined by what is loaded into the SPI partner device (section 12), so the strap is informational. It is kept as a hook for future use or a mismatch check.

---

## 9. The accelerator socket

### 9.1 Purpose
A 16 MB AHB slave window at **0x3000_0000–0x30FF_FFFF** is reserved for a custom accelerator. It was originally intended for a Convolutional Tsetlin Machine accelerator. Any block with an AHB-Lite slave interface can be plugged in. Its registers and buffers then appear as ordinary memory to the CPU and to the debugger, so the accelerator can be configured, fed and read back with plain loads and stores, or by hand from the debugger.

A suggested layout for a full accelerator, as documented in the debugger reference:

| Window | Use |
|---|---|
| 0x3000_0000–0x3000_0FFF | Control / status registers |
| 0x3000_1000–0x300F_FFFF | Input (feature) buffer, about 1 MB |
| 0x3010_0000–0x307F_FFFF | Weights / model parameters, about 7 MB |
| 0x3080_0000–0x30FF_FFFF | Output / results buffer, about 8 MB |

### 9.2 Current occupant: demonstration multiplier
A simple AHB slave, used to prove the socket end to end:

| Offset | Register | Access |
|---|---|---|
| 0x00 | Operand A | Write (and read back) |
| 0x04 | Operand B | Write (and read back) |
| 0x08 | Product A × B (lower 32 bits) | Read |
| 0x0C | Character output (prints in simulation only) | Write |

- **Timing:** zero wait states; the product is computed combinationally and returned in the read's data phase.
- **Uses:**
  - the system-level "profile" test, which times an accelerator access with the CLINT timer;
  - the peripheral test suites;
  - the UVM register model.

### 9.3 Integrating a real accelerator
1. Give the accelerator an AHB-Lite slave interface: select, address, write data, write enable, transfer type and ready in; read data, ready-out and response out.
2. Connect it in place of (or beside) the multiplier on the socket's select / read-data / ready / response signals. The uncore already decodes the whole 16 MB window.
3. If it has an interrupt, route it to a free PLIC source.
4. Map its registers and buffers in software; the debugger can exercise it immediately.

---

## 10. The hardware debugger

### 10.1 Why an in-hardware debugger
- **No external debug tools needed.** The SoC has no JTAG/RISC-V debug module. Instead, a self-contained debugger is built into the chip.
- **What it does:** it listens on a serial link, interprets simple text commands, and acts as a second bus master. It can:
  - read and write any address;
  - upload programs into RAM;
  - halt, step, reset and resume the core;
  - inspect the core's internal state after a crash.
- **Connection:** on the boards, a laptop connects with an ordinary USB-to-serial adapter and a terminal program (e.g. HTerm, PuTTY, minicom) or a Python script.

### 10.2 Building blocks
| Block | Role |
|---|---|
| Link front-ends | Two interchangeable physical links: a **UART** (default 115200 baud, 8N1) and an **FTDI FT1248** synchronous link for high-speed transfers with FT232H/FT2232H chips. A select pin (a slide/DIP switch on the boards) chooses which one is active; the other is isolated. |
| ADP protocol engine | Parses the **ASCII Debug Protocol (ADP)** commands, echoes and formats responses, and runs bulk operations (fill, upload, poll). |
| Bus master | Turns commands into AHB transfers of byte, halfword or word size on the debugger's port of the bus arbiter. |
| Core step controller | Drives the core's freeze input: free-run, halt, single-instruction step, single-clock step, with a watchdog and auto-halt on traps. |
| Core post-mortem debug slave | A read-mostly AHB window at 0x0B00_0000 exposing the core's registers, PCs, CSRs, a trace buffer and sticky crash registers; also holds the debugger's clock-divider registers. |
| Status LEDs (board tops) | Core-halted, link-select, and a serial-activity / prompt-detected indicator. |

### 10.3 Start-up behaviour
On power-up or a board reset, the debugger prints the banner **0x50c1ab04** and immediately enters command mode with the prompt **`]`**; no escape key is needed. Command mode can be left, so that the serial channel acts as a plain terminal, and re-entered with ESC.

### 10.4 Command set (overview)
Commands are single letters followed by an optional hexadecimal parameter, terminated by Enter; they are case-insensitive. The number of hex digits given selects the access size: 2 digits means bytes, 4 means halfwords, 8 means words.

| Group | Command | What it does |
|---|---|---|
| Address | **A** | Set (or show) the address pointer used by the following commands |
| Read/write | **R** | Read one word (or N bytes / halfwords / words) and auto-increment the address |
| | **W** | Write a value and auto-increment |
| Bulk | **V** | Set a reference value (used by fill and poll) |
| | **F** | Fill N words with the reference value (e.g. clear a RAM) |
| | **U** | Upload N raw binary bytes straight from the serial stream into memory (program loading) |
| Wait | **M** + **P** | Set a bit mask, then poll an address until the masked value equals the reference value or a timeout expires (e.g. wait for an accelerator "done" bit) |
| Core control | **C** | Halt, resume, instruction-step, clock-step, assert/release core reset, or query status (see table below) |
| Link speed | **B**, **D** | Read or change the UART baud divider and the FT1248 clock divider at run time |
| Mode | **X** / ESC | Leave / re-enter command mode |

**Core-control sub-commands**

| Action | Command | Effect |
|---|---|---|
| Halt | C 0202 | Freeze all five pipeline stages; the halted LED turns on |
| Resume | C 0102 | Release the freeze |
| Instruction step | C 0204, then C 0104 | Run until exactly one instruction retires, then freeze again |
| Clock step | C 020c, then C 010c | Run for exactly one clock cycle, then freeze again |
| Core reset | C 0201, then C 0101 | Hold the core in reset, then release it. The core restarts in **instruction RAM at 0x8000_0000**, not in the boot ROM |
| Status | C | Report: halted, step busy, step done, crash latched, illegal-instruction flag, misaligned flag, memory-fault flag, trap active |

A bus error during a read or write is shown by an exclamation mark in the response.

### 10.5 Step controller
- **Four states:** running, halted, stepping one instruction, stepping one clock.
- **Instruction stepping** waits for the core's "instruction retired" signal, so one step equals exactly one completed instruction, however many stall cycles it took.
- **Watchdog:** a 65,536-cycle limit ends any step that never completes, for example a step into an endless bus wait, so the debugger can never lock up.
- **Auto-halt on trap:** when an unhandled exception or an illegal instruction is detected, the controller freezes the core in the same cycle. This preserves the crash state instead of letting the program run off into the trap handler or loop forever. Auto-halt on trap and auto-halt on breakpoint (ebreak) can each be switched off.

### 10.6 Post-mortem debug window (0x0B00_0000)
| Region | Contents |
|---|---|
| General registers | All 32 integer registers, read through the register file's second read port without disturbing execution |
| Pipeline | The PC in each of the five stages, the instruction in Decode and in Memory, and stall/flush flags per stage |
| CSRs | Status, cause, trap value, return PC, trap vector, interrupt enable/pending, scratch; 64-bit cycle and retired-instruction counters |
| Debug control | Enable auto-halt on trap; enable auto-halt on breakpoint; clear the sticky crash registers |
| Sticky crash registers | Cause, trap value and faulting PC, latched at the moment of the first trap |
| Link dividers | UART baud divider (16-bit) and FT1248 clock divider (8-bit), writable by both the debugger and the CPU. A baud change only takes effect when the UART is idle, so no character is ever corrupted. |
| Interface status | Which link is selected; whether the core is frozen |
| Trace buffer | A 16-entry circular history of the last retired PCs, plus write pointer and wrap flag |

**Typical crash workflow:**
1. The status query shows "halted + crash latched".
2. Read the latched cause and faulting PC.
3. Dump all 32 registers and the pipeline PCs.
4. Read the 16-entry trace to see the path that led to the crash.
5. Clear the crash registers, fix the program, reload, and reset the core.

The window is also how the SPI boot loader's error state is diagnosed (section 12.7).

### 10.7 Typical debugger session: load and run a program
1. Halt the core.
2. Clear instruction RAM: set the address, set the reference value to zero, fill.
3. Write input data into data RAM.
4. Upload the program binary into instruction RAM.
5. Pulse the core reset; the core restarts at 0x8000_0000.
6. Resume, or step instruction by instruction while reading memory and registers.
7. Halt and read back the results.

The reference example is a 76-byte factorial program: with n = 5, it leaves 120 (0x78) in data RAM.

### 10.8 Host tools
- **Command-line client:** a Python client provides status, halt, step, step-cycle, resume, read, write, accelerator access and divider settings.
- **Automated test script:** a Python script for stepping, clock dividers and post-mortem checks. It runs against a built-in mock (no hardware) or a real board.
- **Terminal:** an ordinary serial terminal for interactive use.

---

## 11. Clocks and resets

### 11.1 Clocking
- **One clock domain:**
  - The whole SoC (core, bus, memories, peripherals, debugger) runs from one clock.
  - There are no gated clocks and no latches, which is good for scan insertion and static timing.
- **Clock frequencies:**
  - On the FPGA boards a clock manager (MMCM) generates **50 MHz** from the board oscillator: 100 MHz on the Basys 3, 125 MHz or 300 MHz on the ZCU102.
  - The ASIC-oriented defaults assume 100 MHz; for example, the debugger's default baud divider differs between the two.
- **Derived rates:**
  - The CLINT timer, the SPI clock and the UART baud rates all derive from this clock through programmable dividers.

### 11.2 Reset sources and what they do
| Reset source | Resets | Core restarts at |
|---|---|---|
| **Power-on / board reset button** (also held while the clock manager is not locked) | Everything: core, bus, memories' control, peripherals, debugger (banner reprinted) | **Boot ROM, 0x0000_1000** |
| **System Control software core reset** (written by firmware or by the debugger) | The core | **Boot ROM, 0x0000_1000** |
| **Debugger core reset** (C 0201 / C 0101) | The core, plus the debugger's crash latches and trace | **Instruction RAM, 0x8000_0000** |

- **Reset synchroniser:** the System Control block synchronises reset release with a two-stage synchroniser and holds reset for 16 more cycles. The boot-mode strap is sampled in this window.
- **Debug versus boot separation (design decision):**
  - The debugger flow (upload a program, reset the core, run it) must never be disturbed by the boot ROM, which would otherwise try to load a program over SPI and overwrite RAM.
  - A flag that survives the core reset therefore records whether the last core reset came from the debugger. The core then starts at 0x8000_0000 for debugger resets and at the boot ROM for every other reset.
  - This change was documented for the team as an RTL change.
- **Documentation note:** some older guides tell the user to program the System Control reset-vector register before a debugger reset. This step is now unnecessary (debugger resets always go to 0x8000_0000) and has no effect (that register is not connected to the core).

---

## 12. The boot flow

### 12.1 Goal
The SoC has no flash memory and its RAMs are empty at power-up. The boot flow brings a program into RAM after every power-up or system reset, without the debugger, by pulling it over SPI from an external "boot partner" device that plays the role of a flash chip.

### 12.2 Building blocks
| Piece | Where it lives | Role |
|---|---|---|
| **Internal boot ROM** | 4 KB hard-wired ROM at 0x0000_1000 | First code after a system reset. Sets the stack, initialises the SPI master, loads one image from SPI, jumps to its entry point |
| **Shared loader** | Part of both boot ROMs | The SPI driver, the stream parser, the bounds checks and the error reporting; identical in both ROMs |
| **External (second-stage) boot ROM** | Sent over SPI; runs from the top 1 KB of instruction RAM (0x8000_7C00) | Optional second stage: re-initialises SPI and loads the next image. A replaceable "ROM" that can be changed without a new chip or bitstream |
| **Boot stream** | Built on the build server by an image tool from the program's ELF file(s) | The byte sequence the partner device clocks out |
| **Boot partner** | Raspberry Pi Pico or Raspberry Pi 4 | Holds the stream in its memory and behaves as an SPI slave |

### 12.3 Stream format
- **One image** consists of:
  1. a 4-byte magic word, the letters **"BOOT"**;
  2. any number of **chunks**, each a 4-byte destination address, a 4-byte size, then that many data bytes;
  3. an **end record**: a 4-byte entry address followed by a size of zero.

  All numbers are little-endian. The image tool makes one chunk per loadable segment of the ELF file, typically one for code and one for initialised data, and rejects any segment outside the two RAM windows.
- **The stream** is one or two images back to back:
  - **Mode 0:** [test image]. The internal ROM loads the program and jumps to it.
  - **Mode 1:** [external boot ROM image][test image]. The internal ROM loads the second-stage ROM and jumps to it at 0x8000_7C00. The second stage then loads the test image from where the stream left off and jumps to it.
- **The mode is decided only by what is in the stream.** The internal ROM always does the same thing: "load one image, jump to it". The board's boot-mode switch is latched by the System Control block but not read by the ROM, so on the current boards it is redundant (kept for future use).

### 12.4 Step by step (one boot)
1. A system reset puts the core at 0x0000_1000.
2. The ROM sets the stack pointer to the top of data RAM and configures the SPI master:
   - SPI mode 3 (clock idles high, data changes on the falling edge, is sampled on the rising edge);
   - 8-bit frames, most significant bit first;
   - chip-select 0;
   - **250 kHz** clock;
   - receive watermark at "one byte".

   It then discards any stale received bytes.
3. The ROM drives **chip-select low** and holds it low for the whole image.
4. **Byte reading:** it reads bytes one at a time. Each read sends a dummy byte, which generates 8 clock pulses; the partner shifts the next stream byte out on the data line. The ROM then waits until the byte has arrived and takes it. Four bytes make a 32-bit word.
5. It checks the magic word. A mismatch is error **E1**.
6. For each chunk, it checks the address and size, then copies the bytes into RAM one by one.
7. At the end record it releases chip-select and jumps to the entry address. Because jumping flushes the pipeline and there are no caches, the freshly written code is fetched correctly.

**Mode-1 hand-over and chip-select.** In mode 1 the second-stage ROM re-asserts chip-select about 100 clock cycles after the internal ROM released it. The SPI controller only changes state on its SPI-clock ticks (every 2 µs at 250 kHz), so chip-select may stay low across the hand-over. The full-SoC boot simulation (suite 09) shows exactly that. It is harmless: the partner's pointer simply continues and the bytes stay aligned. But a partner must not depend on seeing chip-select go high between the two images.

### 12.5 Safety checks
- **Bounds check:** every chunk must lie **entirely inside instruction RAM or entirely inside data RAM**. A chunk is rejected (error **E2**) if:
  - it is larger than a RAM window;
  - it starts below the instruction RAM;
  - it starts in the gap between the two RAMs or above the data RAM;
  - it runs past the end of its window.

  This prevents a corrupted stream from writing over peripherals or wrapping around the address space.
- **Image-tool check:** the image tool enforces the same rule before the stream is ever sent.
- **No checksum:** there is no checksum or CRC in the stream at present (an agreed simplification), so a corrupted data byte would be copied silently. A CRC is a proposed follow-up.

### 12.6 The partner-device rules (agreed protocol)
| Rule | Meaning |
|---|---|
| R1 | The partner keeps a pointer to the next unsent byte. When chip-select goes low again, it **continues** from that pointer (this is what lets the second-stage ROM pick up the second image). |
| R2 | Chip-select going low restarts the **bit** position only (a fresh byte), never the pointer. |
| R3 | The clock is ignored while chip-select is high. |
| R4 | Only reloading the stream from the host rewinds the pointer to the start. **A SoC reset does not rewind the partner**, so every boot is "reload the stream, then reset the SoC". |

### 12.7 Error reporting and diagnosis
- **On error**, the loader:
  - releases chip-select;
  - writes the error code (**0xE1** bad magic, **0xE2** bad chunk address/size) into the **last word of data RAM (0x8001_7FFC)**;
  - stops in an endless loop.
- **Preserved for diagnosis:** the received magic value and the offending address/size are left in core registers, so the debugger can read them through the post-mortem window.
- **Reading a bad magic value:**
  - **all ones:** the partner is not armed or the data line is not connected (it has a pull-up);
  - **a bit-shifted "BOOT":** a clock edge was missed (wiring, ground, timing);
  - **random mid-stream data:** the stream was not reloaded before the reset.

### 12.8 Timing
- **Per byte:** at 250 kHz one byte takes 32 µs on the wire plus the loader's per-byte overhead, about **35–40 µs per byte**.
- **Totals:** a typical 4 KB test loads in about **0.15 s**; a full 64 KB image in about **2.5 s**.
- **Clock history:** the clock was 1 MHz with the Pico. It was lowered to 250 kHz so that the Raspberry Pi 4's software slave has a 2 µs window per bit (section 13.2). The Pico works at any clock.

### 12.9 Robustness fix found during this work (SPI receive race)
- **The problem:**
  - Simulating the loader's exact register sequence against the real SPI controller RTL showed that polling the receive-data register in a tight loop can **lose a byte**.
  - If the byte lands in the receive FIFO exactly between the two clock edges of an APB read, the read removes it from the FIFO but reports "empty".
  - This affects any partner device, the Pico included; in simulation the boot hangs on the first byte.
- **The software fix (already applied):**
  - The loader now waits on the SPI "receive watermark pending" status bit, which has no side effect, and then reads the data register exactly once.
  - It was verified with the real RTL.
- **Recommended RTL fix:** make the controller pop the FIFO only on the access edge and only when it actually returns data. Other software, such as the SPI test program and future drivers, could otherwise still hit the race.

### 12.10 Building the boot ROM
- **Generation:** the internal ROM's contents are generated, not written by hand:
  1. The boot ROM program is assembled.
  2. A generator script converts it into the synthesizable ROM table and a simulation hex file.
- **Build order:** this must be run on the server (it needs the RISC-V toolchain) before the FPGA is built.
- **Current repository state:** this has **not yet been done**. The ROM table still holds an older teammate test ROM: a diagnostic program in one strap position and a simple 0x03-command SPI-flash read in the other. One existing system test depends on that older ROM. Regenerating the ROM is the first step of SPI-boot bring-up (section 16.4).

---

## 13. SPI boot partner devices: Raspberry Pi Pico and Raspberry Pi 4

### 13.1 Raspberry Pi Pico (original partner)
- **Firmware:** flashed once (hold BOOTSEL, plug in USB, copy the firmware file).
- **Receiving a stream:** the stream arrives over the Pico's USB serial port:
  - the host sends "PICO", a 4-byte length, then the stream;
  - the Pico replies **OK**, or **E2** (bad length) / **E3** (timeout);
  - a sliding 4-byte window resynchronises on garbage, and **STAT** reports progress.
- **Serving the stream:**
  - The Pico's chip has a real **hardware SPI-slave** peripheral with an 8-byte FIFO. DMA keeps that FIFO full from a 96 KB buffer, so the CPU never reacts to individual clock edges.
  - On every reload, the SPI block is hardware-reset (rule R4) and DMA is restarted.
- **Host side:** the same image tool builds the stream and, with a serial option, sends it to the device and checks the "OK" reply.

### 13.2 Raspberry Pi 4 (replacement partner, "Case A")
- **Why it is hard:**
  - The Raspberry Pi 4 has no usable SPI-slave peripheral.
  - Under Linux, a program cannot react to clock edges with guaranteed timing.
- **Options studied:**
  - **Case A:** the Pi as a software SPI slave, the SoC unchanged.
  - **Case B:** the Pi as SPI master and the SoC as SPI slave, which needs new SoC hardware.
  - **Others:** a real flash chip programmed by the Pi; keeping the Pico.
- **Choice:** Case A, **bare-metal**. It needs no RTL change.

**How it works**
- **Boot:** the Pi's boot firmware loads our own small 64-bit program from the SD card instead of an operating system.
  1. The program parks three of the four CPU cores.
  2. It disables interrupts.
  3. It enables the instruction cache.
  4. It configures the GPIO pins and a UART.
- **Main loop:** one tight loop owns the CPU.
  - **While chip-select is low (a transfer is running):** the loop does nothing but sample the pins, run the slave state machine, and, on each falling clock edge, set or clear the data-out pin. There are no function calls, no memory accesses, no UART.
  - **While chip-select is high (the bus is idle):** it does all the slow work: the status LED, serial commands, stream reloads, self-timing.
  - **Why this meets the timing:** the SoC always waits at least one SPI clock period after asserting chip-select before the first edge, so the loop always catches up.
- **Host link and serial protocol:**
  - A 3.3 V USB-UART adapter connects to the Pi's UART pins (115200 baud).
  - The protocol is the same as the Pico's (PICO + length + stream → OK/E2/E3; STAT), so the same host tool is used.
  - An extra **TIME** command measures the Pi's own loop speed and reports whether the timing margin is OK.
  - On a timeout the stream is disarmed, so a half-received image is never served.
- **Capacity and status LED:** the stream buffer holds 96 KB. The Pi's green activity LED is on while a stream is armed and not yet fully sent.
- **Wiring (3.3 V logic, common ground mandatory):** the SoC's chip-select, clock, data-out (MOSI, unused) and data-in (MISO) connect to four Pi GPIO pins:

  | SoC signal | Basys 3 (PMOD JC) | ZCU102 (PMOD0 J55) |
  |---|---|---|
  | Chip-select | JC1 | J55.1 |
  | MOSI | JC2 | J55.3 |
  | MISO | JC3 | J55.5 |
  | SCLK | JC4 | J55.7 |

**Verification done without hardware**
| Check | Result |
|---|---|
| Unit tests of the slave state machine on a PC (single image, two images with continuation, reload, interrupted byte, past-the-end, and a timing sweep against a simulated SPI master with jitter) | 33/33 pass |
| Unit tests of the serial protocol with a simulated UART (garbage before a load, keywords inside data, too-long/zero length, timeouts, back-to-back loads, STAT/TIME) | 9/9 pass |
| Mixed simulation: the **real SoC SPI controller RTL** against a timed model of the Pi algorithm (two-image mode-1 run) | Pass at 250 kHz with a 200 ns Pi loop, and still at a 5× slower Pi. Fails, as predicted, at 1 MHz. Exposed the receive race (section 12.9). |
| Compiler warnings on all firmware C files | Clean |

**Still to do:** building the Pi program with the 64-bit ARM cross-compiler on the server, and the bench bring-up (section 16.5).

**Known limits:**
- There is no CRC.
- The Pi serves either SPI or serial at a time, so the stream must be loaded before resetting the SoC.
- Some board details are to be confirmed on the bench: the firmware entry exception level, the UART clock, and the activity-LED pin.

---

## 14. Software and tools

### 14.1 Programming model
- **Instruction set:** bare-metal RV32I (no hardware multiply, divide, compressed or floating-point instructions). Multiplication is done in software with shift-and-add, or offloaded to the accelerator.
- **Memory layout:**
  - Code is linked at 0x8000_0000 (instruction RAM).
  - Data, heap and stack are in 0x8001_0000–0x8001_8000, with the stack growing down from the top.
- **Startup code:** a small startup routine sets the stack and jumps to the program's entry point.

### 14.2 Programs in the repository
| Program | Purpose |
|---|---|
| Factorial (assembly, 76 bytes) | Reference demo for debugger upload and run; n! via shift-and-add |
| Step test (64 bytes) | Deterministic stores used to check single-stepping |
| Trap test | Deliberately causes traps to exercise auto-halt and the post-mortem window |
| Accelerator profile | Times accesses to the accelerator socket with the CLINT timer |
| SPI test | Exercises the SPI master |
| C test program | Uses the multiplier socket and console output; used in simulation |
| Internal and external boot ROMs | The two boot stages sharing one SPI loader |

### 14.3 Tools
| Tool | What it does |
|---|---|
| Software build (make) | Builds all test programs, the two boot ROMs, simulation memory files, and raw binaries for debugger upload |
| ELF-to-memory converter | Produces memory-initialisation files for simulation |
| Boot ROM generator | Turns the assembled internal boot ROM into the synthesizable ROM table plus a hex file |
| Boot image tool | Builds the SPI boot stream (mode 0 or mode 1) from ELF files. Can dump its contents, or send it directly to the Pico/Pi 4 over serial and check the reply |
| Pi 4 helper | Sends STAT and TIME to the Pi 4 partner |
| Debugger CLI and test runner | Python tools for the hardware debugger (section 10.8) |
| Vivado build scripts | One per board: project creation, synthesis, implementation, bitstream; remote programming for the ZCU102 |

### 14.4 Toolchains
| Use | Toolchain |
|---|---|
| SoC software | GNU RISC-V cross-compiler (32-bit RV32I target) |
| Pi 4 partner | 64-bit ARM bare-metal cross-compiler |
| Pico | Pico SDK |
| Simulation | Questa (UVM suites), Icarus Verilog and Verilator (debugger and lightweight testbenches), Vivado XSIM, and the Spike instruction-set simulator as the golden reference |
| FPGA | Vivado |

---

## 15. Verification

Verification is layered from individual blocks up to full-system benchmarks, with independent methods at each level.

### 15.1 Overview
| Layer | What is tested | Method | Recorded outcome |
|---|---|---|---|
| Core unit tests (UVM) | ALU, branch unit, hazard unit, register file | UVM testbenches per unit | Passing |
| 01 Core modules | ALU, branch, immediate extension, subword load/store unit (plus hash units in the component library) | Self-checking, exhaustive or near-exhaustive stimulus | Passing |
| 02 Pipeline hazard stress | Forwarding, load-use, branch collisions, interrupts and exceptions in flight | Hand-crafted corner-case programs + SystemVerilog assertions bound to the pipeline | Passing |
| 03 Architectural compliance | RV32I, Zicsr, machine-mode privileged behaviour | Lock-step comparison against the Spike reference simulator | Passing |
| 04 Bus fabric | 2-master arbiter (priority, contention, core halt), AHB-to-APB bridge | Constrained-random stimulus + AHB/APB protocol checkers | Passing |
| 05 Peripherals | Accelerator socket, GPIO, UART, CLINT, PLIC, System Control, boot ROM | Directed testbenches, SoC-level assembly tests, an SPI flash model | Passing |
| 06 Debugger features | Core freeze, instruction-retired signal, ADP basics | Signal-level timing checks | Passing |
| 07 System C benchmarks | Whole SoC running C programs (hello, 8×8 matrix multiply, quicksort) | Compiled C, UART streaming, pass/fail mailbox | Passing |
| 08 Debugger verification | Full debugger: every command, parser edge cases, both links, bus errors, wait states, random traffic, stepping; and full SoC through the debugger pins | Self-checking block and SoC testbenches with assertions; runs on Icarus and Verilator | **Block: 524 pass, 3 known-bug XFAIL. SoC: 75 pass, 9 XFAIL.** No new failures |
| Standard suites | Industry test suites and benchmarks on the core | See 15.2 | See 15.2 |
| UVM SoC verification | IP unit tests and whole-SoC tests with VIPs | See 15.3 | All listed tests marked passed |
| Static checks | Lint, clock-domain and reset-domain crossing | Spyglass | Reports archived (15.4) |
| Boot flow (this work) | Reset split, System Control boot, ZCU102 board top, Pi 4 partner with real SPI RTL | Icarus testbenches and host unit tests | ZCU102 top 17/17; Pi tests 33/33 and 9/9; RTL SPI simulation pass |

### 15.2 Standard industry suites (core)
| Suite | What it is | Outcome |
|---|---|---|
| RISC-V International architecture tests | Official compliance tests; memory signatures compared with Spike | Signature matches |
| UC Berkeley riscv-tests (user integer tests) | Self-checking tests from the original RISC-V designers; pass/fail through a "to-host" mailbox | Pass |
| EEMBC CoreMark | Industry CPU benchmark (lists, matrix, state machine, CRC) | CPI 1.54, ~204,641 cycles/iteration |
| Dhrystone 2.1 | Classic integer benchmark | CPI 1.55, 0.71 DMIPS/MHz, all 9 result variables correct |
| Embench-IoT (selected kernels) | Modern embedded benchmark suite | crc32 CPI 1.28; matmult-int 1.74; nettle-sha256 1.15; edn 1.73. All bit-exact |
| Google riscv-dv | Random instruction-stream ("torture") generation | Infrastructure present |

### 15.3 UVM verification environment (Questa)
- **Reusable verification IP:** AHB-Lite master, APB master, GPIO pin driver/monitor, interrupt monitor (timer, software, external, GPIO, UART, SPI lines with latency measurement).
- **IP unit tests (7):** GPIO, CLINT, PLIC, System Control, multiplier, UART, SPI. All marked passed.
- **"Coreless" SoC tests (9):** the CPU and debugger are replaced by the AHB VIP, which drives the bus directly. Tests: reset, single read/write, address decoding across all 11 slaves, GPIO, CLINT interrupts, PLIC routing and claim, ROM remap, concurrency stress, and a full suite. All marked passed. The environment includes a register model, a scoreboard with shadow memory, functional coverage, and protocol assertions.
- **Full-core SoC tests:** the real CPU runs C firmware inside the UVM environment. Tests: boot/bring-up, CLINT (timer and software interrupts), GPIO, PLIC, SPI, UART, stress, and an all-peripheral suite.
- **Caveat:** this environment uses its own snapshot copy of the RTL, which has drifted from the main source tree. Results should be refreshed after re-syncing (section 18).

### 15.4 Static analysis and design visualisation
- **Spyglass:** reports for lint (several rule sets), clock-domain crossing and reset-domain crossing on the full SoC top, using a constraints file for the design.
- **Schematics:** exported from Vivado.
- **RTLvision PRO views:** available for reviews and presentations.

### 15.5 Known open bugs tracked by the debugger regression
| Tag | Issue |
|---|---|
| N2 | An all-ones undefined opcode is not reported as an illegal instruction |
| N3 | The core can change an AHB request while the bus is holding it in a wait state (protocol rule violation) |
| N8 | After returning from an interrupt the program does not always resume exactly where it was interrupted |
| N9 | A misaligned jump target is not flagged and halted as documented |
| A3 | No default slave: unmapped addresses do not return a bus error |
| C11 | Minor mismatches between the debugger command reference and the RTL |

Each is reproduced by a test marked "expected failure". When a bug is fixed, the test reports an unexpected pass and the tag is removed.

---

## 16. FPGA prototyping and bring-up

### 16.1 Shared approach
- **Same RTL as simulation:** both boards use the same SoC RTL as simulation, with a thin board "top". The board top:
  - generates 50 MHz with a clock manager;
  - combines the reset button with "clock locked";
  - registers asynchronous inputs;
  - maps the debugger link, SPI, app UART and FT1248 to board connectors;
  - drives status LEDs.
- **Memories** map onto FPGA block RAM.
- **The boot ROM** is plain logic, so no memory-initialisation files are needed.

### 16.2 Digilent Basys 3 (Artix-7 35T): primary, proven board
| Function | Board resource |
|---|---|
| Clock | 100 MHz oscillator → MMCM → 50 MHz |
| System reset | Centre push-button |
| Debugger link select | Slide switch 0 (UART / FT1248) |
| Boot-mode strap | Slide switch 1 (informational, see 12.3) |
| Debugger UART | USB-UART dongle on PMOD JA |
| FT1248 | PMOD JB |
| SPI boot | PMOD JC (CS, MOSI, MISO, SCLK) |
| LEDs | Core halted; FT1248 selected; serial activity / prompt detected |

The debugger-driven flows (upload, run, step, post-mortem, baud changes) are demonstrated on this board.

### 16.3 AMD ZCU102 (Zynq UltraScale+): second board, "to be tested"
- **Design:** a programmable-logic-only port of the Basys design; the board's ARM processing system is not used. Pins come from the board user guide's master constraints listing.
- **Remote build, local board:**
  - The code and Vivado live on a remote server; the board sits on a lab bench.
  - The bench PC runs AMD's **hardware server** (network port 3121), so the remote Vivado can program the board's JTAG over the network.
  - Buttons, switches and LEDs are used by hand.

| Function | ZCU102 resource |
|---|---|
| Clock | 125 MHz fixed oscillator → MMCM → 50 MHz (fallback: the 300 MHz SI570 oscillator) |
| System reset | CPU_RESET push-button (SW20) |
| Link select / boot strap | DIP switch SW13 positions 1 and 2 |
| Debugger UART | On-board CP2108 USB-UART, channel 2 (third of four serial ports on the micro-USB connector J83) |
| SPI boot | PMOD0 (J55) odd pins |
| FT1248 | PMOD0 even pins |
| App UART | PMOD1 |
| LEDs (8) | Halted, link select, serial activity, boot strap, clock OK, trap seen, SPI activity, heartbeat |
| On-chip logic analyser | Optional ILA probes: SPI and UART pins, PC, and status (reset, lock, strap, link select, trap, halted) |

- **Board setting:** the processing-system boot-mode switch must be set to JTAG.
- **Build flow:** one make command builds the bitstream and stops on failed runs or negative timing slack; another programs the board through the hardware server.
- **Verified in simulation (17/17 checks):**
  - banner on the USB-UART;
  - debugger write/read-back;
  - halt/resume LED;
  - reset re-banner;
  - strap latch and SPI activity;
  - link-select LED;
  - app UART pin;
  - heartbeat.

  The clock path elaborates in all four configurations, and every port has exactly one pin.
- **Not yet run in Vivado.** A possible I/O-standard issue on the 125 MHz clock input is anticipated, with the SI570 clock as the fallback.

### 16.4 Bring-up sequence (recommended order)
1. **Program and alive:** clock-OK and heartbeat LEDs come on; the terminal shows the banner and the prompt.
2. **Debugger bus access:** write and read back data RAM; read the System Control chip ID (0x1709_50C1).
3. **Core control:** halt/resume (LED), core reset, instruction and clock stepping with the step test.
4. **Run a program:** upload the factorial program and check 5! = 120.
5. **Crash path:** run the trap test; confirm auto-halt, the latched cause/PC and the trace buffer.
6. **Accelerator socket:** write operands and read the product through the debugger.
7. **Boot ROM:** regenerate the ROM (section 12.10) and rebuild. Then:
   - With nothing attached: a system reset should give error E1 with an all-ones magic (proves the ROM runs and SPI is driven).
   - With the partner attached and a mode-0 stream loaded: the test program runs after reset.
   - Then the same with a mode-1 stream (second-stage ROM).
8. **Observe:** use the ILA (ZCU102) or a logic analyser on chip-select, clock and data to confirm the 250 kHz clock and the per-image chip-select framing.

### 16.5 Raspberry Pi 4 bench bring-up
1. **Pi alone:** the terminal shows the ready banner; TIME reports "margin OK", with the worst reaction time well below the 2 µs budget. If not, force the Pi's turbo clock or halve the SPI clock again.
2. **Load:** the host tool reports OK; STAT shows the stream armed with nothing sent.
3. **Boot:** reset the SoC. STAT shows everything sent; the activity LED goes off; check the program's results through the debugger.
4. **On error E1:** read the received magic through the post-mortem window and diagnose as in section 12.7.

---

## 17. End-to-end workflow: server, lab and board

```
  REMOTE SERVER (code, toolchains, Vivado)
    1. build software, boot ROMs, boot streams; regenerate the ROM table
    2. build the FPGA bitstream (Basys 3 or ZCU102)
    3. (ZCU102) program the board over the network via hw_server :3121
    4. build the Pi 4 SD-card image
                 |  files copied to the lab laptop
                 v
  LAB LAPTOP / BENCH PC
    - runs hw_server (ZCU102 JTAG), or programs the Basys 3 locally
    - serial terminal / Python CLI for the debugger
    - image tool sends the boot stream to the Pico / Pi 4 over serial
                 |
                 v
  BOARD (SoC on FPGA)  <-- SPI (250 kHz, mode 3) --  boot partner (Pico / Pi 4)
         ^
         | debugger UART / FT1248
```

**Two ways to get a program running:**
- **Debugger path** (development): halt → upload over serial → debugger core reset → run or step. The boot ROM is never involved.
- **Boot path** (stand-alone): load the stream into the partner → press the system reset → the boot ROM pulls the program over SPI → runs. Each further boot is "reload, then reset".

---

## 18. Known issues, limitations and open items

| Area | Item | Impact / next step |
|---|---|---|
| Boot ROM | ROM table not yet regenerated from the current boot loader; still holds the older teammate ROM | SPI boot with the Pico/Pi 4 will not work until it is regenerated; one older system test depends on the old ROM and must be updated |
| SPI controller | Receive-data read race can lose a byte | Fixed in the boot loader; RTL fix recommended for all other software |
| Boot stream | No CRC/checksum | A corrupted byte is copied silently; CRC proposed as a follow-up |
| App UART | The SoC builds a register-only UART model (no serial output on hardware) | Switch to the full 16550 core (one parameter) and verify |
| System Control | Reset-vector register and clock-gating mask not connected | Either connect them or document them as reserved; old guides mention the reset vector |
| Boot strap | Not read by the boot ROM | Redundant on current boards; kept as a hook |
| GPIO documentation | README describes an XOR (polarity) register that the RTL does not have | Correct the documentation (or add the register) |
| Bus | No default slave: unmapped addresses read as zero without an error (A3) | Add an error-responding default slave |
| Core | Open bugs N2, N3, N8, N9 (section 15.5) | Fix and remove the expected-failure tags |
| Verification | UVM environment uses a diverged RTL copy | Re-sync and re-run the regression |
| Docs | Some documents still describe a 1 MHz boot SPI clock, 8 KB RAMs, or the reset-vector step | Update when the design is frozen |
| Hardware | ZCU102 build, Pi 4 partner, regenerated boot ROM: not yet run on real hardware; ZCU102 Vivado build not yet run | Follow the bring-up sequences in 16.4 and 16.5 |
| Accelerator | Socket holds a demonstration multiplier | Integrate the real accelerator (section 9.3) |

---

## 19. Glossary
| Term | Meaning |
|---|---|
| ADP | ASCII Debug Protocol: the text command language of the hardware debugger |
| AHB-Lite | AMBA Advanced High-performance Bus, single-master variant; the SoC's main bus |
| APB | AMBA Advanced Peripheral Bus; a simple, slower bus for peripherals |
| BRAM | Block RAM: dedicated memory blocks inside an FPGA |
| CLINT | Core-Local Interruptor: the RISC-V timer and software-interrupt block |
| CPI | Cycles per instruction (lower is better; 1.0 is ideal for a scalar pipeline) |
| CSR | Control and Status Register (RISC-V privileged state) |
| DMIPS/MHz | Dhrystone millions of instructions per second, per MHz of clock |
| ELF | Executable and Linkable Format: the compiler's output file |
| FT1248 | FTDI's synchronous serial interface for its USB bridge chips |
| hw_server | AMD/Xilinx hardware server; exposes a board's JTAG over the network |
| ILA | Integrated Logic Analyzer: an on-chip logic analyser in the FPGA |
| MMCM | Mixed-Mode Clock Manager: the FPGA's clock synthesiser |
| PLIC | Platform-Level Interrupt Controller |
| PMOD | Digilent's 12-pin peripheral connector standard |
| RV32I | 32-bit RISC-V base integer instruction set |
| SPI mode 3 | Clock idles high; data changes on the falling edge and is sampled on the rising edge |
| SVA | SystemVerilog Assertions |
| UVM | Universal Verification Methodology (SystemVerilog) |
| VIP | Verification IP: reusable bus/pin models for testbenches |
| XFAIL | "Expected failure": a test that reproduces a known, tracked bug |
| Zicsr | RISC-V extension for CSR access instructions |

---

## 20. Quick-reference appendix

**Key numbers**
| Item | Value |
|---|---|
| ISA / privilege | RV32I + Zicsr / machine mode |
| Pipeline | 5 stages, forwarding, branch resolved in Execute, 1-cycle load-use stall |
| Clock (FPGA) | 50 MHz |
| RAM / ROM | 32 KB + 32 KB / 4 KB |
| Accelerator window | 16 MB at 0x3000_0000 |
| Dhrystone | 0.71 DMIPS/MHz (CPI 1.55) |
| CoreMark | CPI 1.54 |
| Debugger link | UART 115200 8N1 (adjustable up to 3 Mbaud) or FT1248 |
| Debugger banner / prompt | 0x50c1ab04 / `]` |
| Chip ID | 0x1709_50C1 |
| Boot SPI | Mode 3, 8-bit, MSB first, 250 kHz, CS0 held low per image |
| Boot error word | 0x8001_7FFC (E1 bad magic, E2 bad chunk) |
| Second-stage ROM location | 0x8000_7C00 (top 1 KB of instruction RAM) |
| Reset start addresses | System/soft reset → 0x0000_1000; debugger core reset → 0x8000_0000 |

**Memory map (short):** boot ROM 0x0000_1000 · CLINT 0x0200_0000 · core debug 0x0B00_0000 · PLIC 0x0C00_0000 · UART 0x1000_0000 · SPI 0x1004_0000 · GPIO 0x1006_0000 · SYSCTRL 0x1008_0000 · accelerator 0x3000_0000 · IRAM 0x8000_0000 · DRAM 0x8001_0000.

**Suggested slide outline (if building a deck from this document)**
1. Title and motivation: an accelerator control SoC.
2. Top-level block diagram (3.1).
3. Memory map (4.1).
4. Core pipeline and hazards (5.2–5.4).
5. Traps and interrupts (5.5).
6. Bus fabric and arbitration (6).
7. Peripherals at a glance (8).
8. Accelerator socket (9).
9. Hardware debugger: features and commands (10).
10. Post-mortem debugging (10.6).
11. Reset scheme: debug versus boot (11.2).
12. Boot flow and stream format (12.3–12.4).
13. Boot safety, errors and timing (12.5–12.8).
14. Boot partners: Pico versus Pi 4 (13).
15. Verification pyramid (15.1).
16. Benchmarks (15.2).
17. UVM environment (15.3).
18. FPGA platforms (16.2–16.3).
19. Bring-up plan (16.4–16.5).
20. Open items and next steps (18).
