# 1TOPS SoC on the AMD ZCU102

The same 1TOPS SoC as the Basys 3 build (`fpga/`): RTL from `source/`, the internal boot ROM, the debugger and SPI boot.
Here it runs on the ZCU102 (`xczu9eg-ffvb1156-2-e`).

**Setup:**

```
  Remote server (code + Vivado)                      Lab bench
 ┌───────────────────────────┐   network    ┌─────────────────────────────┐   USB-JTAG (J2)  ┌─────────┐
 │ make build_fpga           │ ───────────▶ │ PC running hw_server        │ ───────────────▶ │ ZCU102  │
 │ make stream_remote ───────┼── :3121 ───▶ │ 10.10.92.226:3121           │   USB-UART (J83) │         │
 └───────────────────────────┘              │ HTerm (debugger console)    │ ◀──────────────▶ │         │
                                            └─────────────────────────────┘                  └─────────┘
                                                                         buttons, switches, LEDs: by hand
```

The board is on the bench: buttons, switches and LEDs are used directly, as on the Basys 3. Only Vivado and the code
are far away. `hw_server` lets the remote Vivado program the board's JTAG. The Zynq ARM side (PS) is **not used**:
this is a PL-only design, like the Basys 3 build.

## 1. Basys 3 → ZCU102 mapping

| Function | Basys 3 | ZCU102 (UG1182 net / pin) | Where on the board |
|---|---|---|---|
| Clock | 100 MHz W5 → MMCM → 50 MHz | `CLK_125` G21/F21 (125 MHz) → MMCM → **50 MHz** | U69 oscillator (fixed) |
| Reset (btnC) | U18 | `CPU_RESET` AM13, active high | **SW20** "CPU_RESET" pushbutton |
| dbg_sel (SW0) | V17 | `GPIO_DIP_SW0` AN14 | **SW13 position 1** (0 = UART, 1 = FT1248) |
| boot_mode (SW1) | V16 | `GPIO_DIP_SW1` AP14 | **SW13 position 2** |
| Debugger UART (HTerm) | USB-UART B18/A18 | CP2108 **channel 2** (PL side): `UART2_TXD_O_FPGA_RXD` E13 (FPGA RX), `UART2_RXD_I_FPGA_TXD` F13 (FPGA TX) | micro-USB **J83** |
| App UART (UARTSin/out) | PMOD JA 1/2 | `PMOD1_0` D20 (in) / `PMOD1_1` E20 (out) | **J87.1 / J87.3** → USB-UART dongle |
| SPI boot (to the Pico) | PMOD JC 1–4 | `PMOD0_0..3` A20/B20/A22/A21 | **J55.1 / .3 / .5 / .7** |
| FT1248 | PMOD JB 1–4 | `PMOD0_4..7` B21/C21/C22/D21 | **J55.2 / .4 / .6 / .8** |
| LEDs | LED0, LED1, LED15 | `GPIO_LED_0..7` | **DS37…DS44** (table below) |

**LEDs (`GPIO_LED_n`):**

| LED | Meaning | Basys 3 equivalent |
|---|---|---|
| 0 | Core halted (by the debugger, or auto-halt on a trap) | LED0 |
| 1 | dbg_sel (SW13.1) | LED1 |
| 2 | Debugger UART RX: blinks on each received byte, latches on `]` | LED15 |
| 3 | boot_mode (SW13.2) | — |
| 4 | Clock OK (MMCM locked) | — |
| 5 | A trap happened since the last reset | — |
| 6 | SPI activity (~200 ms blink while CS is asserted) | — |
| 7 | Heartbeat ~1.5 Hz: the 50 MHz clock is running | — |

All pins and I/O standards come from **UG1182 (v1.2), Appendix B "Master Constraints File Listing"**. They are copied
unchanged into `constrs/`, and the top-level port names are the UG1182 net names.

## 2. Files

| File | Role | Based on |
|---|---|---|
| `top/tops_soc_zcu102_top.sv` | Board top: clock, reset, LEDs, SoC | Basys `fpga/top/tops_soc_fpga_top.sv`. Its LED/UART-monitor block is copied verbatim (marked in the file). |
| `constrs/zcu102_pinmap.xdc` | Board I/O pins + pulls | UG1182 Appendix B |
| `constrs/zcu102_clk125.xdc`, `zcu102_si570.xdc` | Clock pins + `create_clock`; one is used, per `CLK_SRC` | UG1182 Appendix B |
| `constrs/zcu102_timing.xdc` | Asynchronous-I/O false paths | Basys `basys3.xdc` §8 |
| `build_zcu102.tcl` | Vivado project → bitstream; stops on failed runs or negative slack | Basys `fpga/build_fpga.tcl` |
| `Makefile` | `code`, `rom`, `build_fpga`, `stream_remote`, `sim`, `clean_fpga` | nanosoc `makefile.fpga` |
| `makefile.targets`, `hw_server.tcl` | Part selection and remote programming | nanosoc, **used unchanged** |
| `sim/` | iverilog testbench of the top (`make sim`) | — |

The nanosoc reference files (`makefile.fpga`, `vivado_script/nanosoc_design.tcl`, `fpga_pinmap.xdc`,
`fpga_timing.xdc`) are kept as-is for reference and are not used by this build.

## 3. Build and program (on the remote server)

```bash
cd fpga/zcu102
make code                 # software: boot ROMs + tests (RISC-V toolchain)
make rom                  # write the SPI boot ROM into source/uncore/rom_ahb.sv (see caveat 1)
make build_fpga           # -> output/tops_soc_zcu102.bit (+ .ltx), timing/utilization reports
make stream_remote        # program the ZCU102 through hw_server 10.10.92.226:3121
```
Options:
- `CLK_SRC=SI570`: use the 300 MHz SI570 clock instead of CLK_125 (see caveat 2).
- `ENABLE_ILA=0`: build without the ILA.
- `JOBS=16`, `ALLOW_TIMING_FAIL=1`.
- `HW_SERVER=host:3121`: use a different hw_server.

## 4. On the bench

1. **Boot-mode switch SW6 = JTAG** (`SW6[4:1]` = on, on, on, on; UG1182 Table 2-4), so the PS doesn't try to boot
   from QSPI/SD while the PL is programmed over JTAG.
2. Connect micro-USB **J2** (JTAG) to the hw_server PC, and micro-USB **J83** (USB-UART) to the PC running HTerm.
   J83 shows up as **four** serial ports (CP2108 channels 0–3). The debugger is on **channel 2**, normally the
   **third** of the four (e.g. `/dev/ttyUSB2`, or the third new COM port). HTerm settings: **115200, 8N1, no flow
   control**, the same as on Basys 3.
3. After `make stream_remote`: **LED4** (clock OK) and **LED7** (heartbeat) come on, and HTerm shows ` 0x50c1ab04`
   then `]`. Press **SW20 CPU_RESET** at any time to get the banner again (the btnC equivalent).
4. Use the debugger exactly as on Basys 3 (`source/debugger/COMMANDS.md`), e.g. the factorial / step_test flows.
   Note the data RAM is at **`0x8001_0000`** in this repo.
5. **SPI boot with the Pico:** wire the Pico to PMOD0 J55: CS = J55.1, MOSI = J55.3, MISO = J55.5, SCK = J55.7, plus
   GND (see UG1182 Figure 3-28 for the J55 GND/3.3 V pins). Load the Pico with `software/make_image.py … --serial`,
   then press SW20.
6. **ILA (optional):** in Vivado Hardware Manager on the server, connect to `10.10.92.226:3121`, open the target and
   set the probes file to `output/tops_soc_zcu102.ltx`. Probes:
   - `probe0` = {SPI cs_n, mosi, miso, sclk, debugger UART rx/tx, app UART in/out};
   - `probe1` = PC;
   - `probe2` = status {reset, clock locked, boot_mode, dbg_sel, trap seen, halted, TrapM}.

## 5. Caveats

1. **Boot ROM contents.** `source/uncore/rom_ahb.sv` still holds the teammate's dual-mode test ROM until `make rom`
   (`make -C software rom`) is run with the RISC-V toolchain. Until then the SPI/Pico boot flow doesn't run:
   - **SW13.2 = 0:** the ROM's diagnostic `main` runs.
   - **SW13.2 = 1:** the old `0x03` 32-byte flash read runs. **With the Pico attached, keep SW13.2 = 0**, otherwise
     the old ROM consumes the first 36 bytes of the Pico's stream.

   The debugger flow works either way: a debugger core reset starts at `0x8000_0000`. See the caveat section in
   `changes_s1.md`.
2. **CLK_125 I/O standard.** UG1182 constrains CLK_125 (bank 47, an HD bank at 3.3 V) as `LVDS_25`, and we use it
   unchanged. If Vivado reports that LVDS_25 is not allowed in this HD bank (an AMD forum thread reports this), build
   with `CLK_SRC=SI570`. That uses the USER_SI570 oscillator (AL8/AL7, `DIFF_SSTL12`, HP bank 64, **300 MHz at
   power-up**; it is I2C-programmable, so it must not have been reprogrammed). No RTL edits are needed.
3. **The nanosoc `fpga_pinmap.xdc` is not used.** Apart from its PMOD0 lines, its long commented section is the
   **ZCU104's** listing: for example, PMOD1 there is J9…M9, while UG1182 gives D20/E20/D22/E22/F20/G20/J20/J19.
4. **Not yet run in Vivado** (no Vivado on the authoring machine). The RTL is verified (below); the Tcl uses only
   standard project-mode commands and one IP (ILA).

## 6. Verified here (iverilog, no Vivado)

- **`make sim`: 17/17 checks pass** on the real SoC RTL through `tops_soc_zcu102_top`, with the testbench playing the
  board and HTerm:
  - banner on the USB-UART;
  - ADP write/read-back of DMEM; LED2 on RX activity;
  - `C 0202`/`C 0102` → LED0;
  - CPU_RESET → banner again;
  - SW13.2 → LED3, SYSCTRL strap latched, the boot ROM driving SPI on PMOD0, LED6;
  - SW13.1 → LED1;
  - app UART on PMOD1;
  - heartbeat.
- **The FPGA-only clock path** (`IBUFDS` → `MMCME4_BASE` → `BUFG`) elaborates with port-compatible stand-ins in all
  four configurations (CLK125/SI570 × with/without ILA). MMCM settings: 125 MHz × 8 / 20 = 50.00 MHz (VCO 1000 MHz),
  and 300 MHz × 4 / 24 = 50.01 MHz (VCO 1200 MHz).
- **Every top-level port has exactly one UG1182 pin** in both clock configurations (25 ports, 25 pins).
