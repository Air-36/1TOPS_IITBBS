# 1TOPS SoC: SPI Boot on the Basys 3 with a Raspberry Pi 4, the Full Guide

This guide covers the whole bench setup, from the source tree to a test program that boots over SPI and passes on real hardware. Follow it in order. Each step states what you should see. The **Troubleshooting** section (Part P) lists every failure met while bringing this up: what causes it, what it looks like, and how to fix it.

Verified on 2026-11-14 (Basys 3 + Pi 4 Model B):
- mode-0 boot;
- mode-1 boot, 5 runs in a row;
- the `boot_e2e` self-check test;
- the `factorial` program.

The ZCU102 part (Part Q) is prepared but **not yet bench-verified**.

---

## Contents
- [0. What you are building](#0-what-you-are-building)
- [1. Machines, hardware and software](#1-machines-hardware-and-software)
- [2. Safety rules (read before touching any wire)](#2-safety-rules-read-before-touching-any-wire)
- [A. Server: environment](#a-server-environment)
- [B. Server: FPGA bitstream](#b-server-fpga-bitstream)
- [C. Server: Raspberry Pi firmware and SD-card files](#c-server-raspberry-pi-firmware-and-sd-card-files)
- [D. Server: test programs](#d-server-test-programs)
- [E. Write the SD card](#e-write-the-sd-card)
- [F. Lab PC: one-time setup](#f-lab-pc-one-time-setup)
- [G. Lab PC: copy the bench files and create the helper scripts](#g-lab-pc-copy-the-bench-files-and-create-the-helper-scripts)
- [H. Wiring](#h-wiring)
- [I. Program the FPGA](#i-program-the-fpga)
- [J. Find the serial ports](#j-find-the-serial-ports)
- [K. Bring-up checks](#k-bring-up-checks)
- [L. Test 1: boot_e2e (mode 0 and mode 1)](#l-test-1-boot_e2e-mode-0-and-mode-1)
- [M. Test 2: factorial](#m-test-2-factorial)
- [N. Booting your own program](#n-booting-your-own-program)
- [O. Daily quick start](#o-daily-quick-start)
- [P. Troubleshooting: every error we hit](#p-troubleshooting-every-error-we-hit)
- [Q. ZCU102 (next board, not yet bench-verified)](#q-zcu102-next-board-not-yet-bench-verified)
- [R. Reference](#r-reference)

---

## 0. What you are building

```
   SERVER (Vivado, compilers)                         LAB PC (Linux, on the bench)
   ─────────────────────────                          ────────────────────────────
   build bitstream ──── network :3121 ──────────────▶ hw_server ──USB(JTAG)──▶ Basys 3 FPGA
   build Pi firmware ─┐                                                         (the 1TOPS SoC)
   build test programs├── scp ─────────────────────▶ ~/bench/                    │  ▲
                      └── scp ──▶ (any PC with an SD reader) ──▶ SD card ──▶ Pi 4│  │SPI
                                                                                 │  │(PMOD JC)
   LAB PC:  make_image.py ──USB-UART adapter──▶ Pi 4 (stores the boot stream) ◀──┘  │
            dbg.py ────────Basys USB (UART)──▶ SoC debugger (reads results) ────────┘
```

**The boot sequence:**
1. `make_image.py` packs a RISC-V program into a *boot stream* and stores it in the Pi's memory. The Pi waits.
2. You press **btnC**, which resets the SoC. The CPU starts in the internal boot ROM at `0x0000_1000`.
3. The boot ROM reads the stream from the Pi over SPI (250 kHz), copies each chunk into RAM, checks the addresses, and **jumps to the program in RAM**. If something is wrong, it writes an error code to `0x8001_7FFC` instead.
4. The program runs. You read its results through the debugger.

There are two boot modes:
- **Mode 0** loads the program directly.
- **Mode 1** first loads a small second-stage ROM into the top 1 KB of instruction RAM (`0x8000_7C00`). That second-stage ROM then reads and loads the program.

---

## 1. Machines, hardware and software

| Machine | Used for | Needs |
|---|---|---|
| **Server** (`vlsi-srv.iitbbs.ac.in`, also reachable as `10.10.36.213`) | Building everything; programming the FPGA remotely | Vivado 2024.2, a RISC-V GCC, an AArch64 bare-metal GCC, python3 + pyelftools, iverilog (optional), internet access (to download the Pi firmware) |
| **Lab PC** (Linux, on the bench) | USB connection to the Basys and the Pi; sending streams; reading results | python3 + pyserial + pyelftools, `ssh`/`scp`, `hw_server` (Vivado Lab Solutions) and the Digilent cable drivers |
| **Any PC with an SD-card reader** (we used a separate Windows PC because the lab PC's USB ports were full) | Writing the Pi's SD card | `scp` (built into Windows 10/11 PowerShell) or WinSCP |

**Hardware:**
- **Digilent Basys 3** (xc7a35t) and its micro-USB cable. It **must be a data cable**: charge-only cables power the board but carry no data.
- **Raspberry Pi 4 Model B**. Ours was rev 1.5 4 GB (`boardrev d03115`). You also need its **own USB-C power supply** (5 V, 3 A) and a microSD card.
- **One USB-UART adapter with 3.3 V logic.** We used a CH340 board (USB ID `1a86`). CP2102, FT232 and PL2303 adapters also work, as long as the logic level is 3.3 V.
- **Female–female jumper wires:** 5 between the Basys and the Pi, and 3 between the adapter and the Pi.

In this guide, replace these placeholders with your own values:

| Placeholder | Meaning | Example |
|---|---|---|
| `<user>` | your login on the server | `23EC01058` |
| `<REPO>` | the repo path on the server, relative to your home | `avp_projects/1TOPS-Final-SoC/1TOPS_IITBBS` |
| `<LABPC_IP>` | the lab PC's IP address (it can change: DHCP) | `10.10.92.226` |

---

## 2. Safety rules (read before touching any wire)

1. **One power source per board. Never two.**
   - **Basys 3:** power it only from the micro-USB cable in port **J4 "PROG UART"**, with jumper **JP2 on "USB"**. Do not also connect an external supply or battery to it.
   - **Pi 4:** power it only from its own USB-C supply.
   - **Never connect any VCC, 3.3 V or 5 V pin between the boards, or from the adapter to anything.** Two supplies joined together fight each other and can destroy a board.
2. **Everything on the signal wires is 3.3 V.**
   - The Pi's GPIO pins are **not 5 V tolerant**.
   - The USB-UART adapter must send **3.3 V** signals. If it has a 3V3/5V jumper or switch, set it to **3V3**. If you have a multimeter, measure the adapter's TX pin against its GND, with the adapter plugged into the PC and nothing else connected. It must read about 3.3 V, never 5 V.
   - The adapter's **VCC/5V/3V3 pin stays unconnected**. On 4-wire cables, the **red** wire is 5 V: leave it loose and tape it.
3. **Pi header pins 2 and 4 carry 5 V; pins 1 and 17 carry 3.3 V.** No wire from this setup goes on any of them.
4. **Basys PMOD pins 6 and 12 carry 3.3 V.** Never connect them to the Pi.
5. **Wire everything with all power off**, and re-check the wiring before powering up.
6. **A common ground is required.** Basys PMOD GND goes to Pi GND, and adapter GND goes to Pi GND. Without it, signals are unreliable or don't work at all.
7. **Power order:**
   - **Power on:** Pi first, then the Basys. This way the Basys never drives 3.3 V into an unpowered Pi.
   - **Power off:** Basys first, then the Pi.
   - **Program the FPGA before you arm the Pi.** While the FPGA is being configured, its CS and SCLK pins float.

---

## A. Server: environment

Log in to the server (`ssh <user>@vlsi-srv.iitbbs.ac.in`) and go to the repo:
```bash
cd ~/<REPO>
```

**A.1 Vivado on PATH.** Use whatever your server provides, for example:
```bash
module load vivado/2024.2        # check the name with: module avail vivado
which vivado                     # must print a path
```

**A.2 RISC-V GCC.** We used the xPack `riscv-none-elf-gcc` 15.2 in `~/riscv_toolchain/bin`. Any bare-metal RISC-V GCC that supports `-march=rv32i` works. Install one if you don't have it, from <https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases>, or ask a teammate for the path of an existing install.
```bash
export PATH=$HOME/riscv_toolchain/bin:$PATH
ls $HOME/riscv_toolchain/bin/*gcc
```
**Set `RV` to the part of the gcc file name before `gcc`.** For example, if `ls` shows `riscv-none-elf-gcc`:
```bash
export RV=riscv-none-elf-
```
This toolchain has no `size` or `nm` binaries. The Makefiles detect that and fall back automatically, so you don't need to do anything.

**A.3 AArch64 bare-metal GCC (for the Pi).** This is the Arm GNU Toolchain 13.3.rel1 (`aarch64-none-elf`):
```bash
# one-time install into ~/tools (skip if you already have it)
mkdir -p ~/tools && cd ~/tools
wget https://developer.arm.com/-/media/Files/downloads/gnu/13.3.rel1/binrel/arm-gnu-toolchain-13.3.rel1-x86_64-aarch64-none-elf.tar.xz
tar xf arm-gnu-toolchain-13.3.rel1-x86_64-aarch64-none-elf.tar.xz
cd ~/<REPO>
# every session:
export PATH=$HOME/tools/arm-gnu-toolchain-13.3.rel1-x86_64-aarch64-none-elf/bin:$PATH
aarch64-none-elf-gcc --version   # must print a version
```

**A.4 Python.** `make_image.py` needs pyelftools:
```bash
python3 -c "import elftools; print('pyelftools ok')" || python3 -m pip install --user pyelftools
```

**A.5 Check that the boot ROM in the RTL is the SPI loader.** The FPGA's internal ROM is generated into `source/uncore/rom_ahb.sv`. It must hold the SPI loader, not an older test ROM:
```bash
grep -c "32'h8001_8137" source/uncore/rom_ahb.sv     # must print 1 (or more)
```
If it prints `0`, regenerate the ROM (`make -C software rom RISCV_PREFIX=$RV`), then rebuild the bitstream. **Symptom if you skip this:** the debugger works, but nothing is ever loaded from the Pi.

---

## B. Server: FPGA bitstream

**B.1 Optional but recommended: simulate the board top first** (needs iverilog, about 1 minute):
```bash
make -C fpga sim
```
Expect `=== RESULT: ALL PASS (0 failures) ===` (15 checks: banner, debugger W/R, halt/resume, btnC, SPI activity on PMOD JC with error E1, SW0, app UART).

**B.2 Build the bitstream.** This takes a while, so run it in the background:
```bash
nohup make -C fpga build_fpga > nohup_basys.out 2>&1 &
tail -f nohup_basys.out          # Ctrl+C stops watching; the build keeps running
```

**B.3 Check the result:**
```bash
grep -E "Timing: WNS|build complete|ERROR" nohup_basys.out
ls -l fpga/output/tops_soc_basys3.bit
```
You need all three of these:
- **`Timing: WNS = <x> ns, WHS = <y> ns` with both x and y ≥ 0.** If timing fails, the script stops with `Timing NOT met`.
- **`Basys 3 build complete: .../fpga/output/tops_soc_basys3.bit`**
- **The `.bit` file exists**, about 2.1 MB. Ours was 2,192,125 bytes.

Optionally, check that the RAMs became block RAM: `grep -i "Block RAM" fpga/output/utilization.rpt` must show tiles in use. An old bug sized the RAMs at 64 words (256 B) under Vivado; that bug is fixed in the repo (Part P, B3).

**The bitstream stays on the server.** Part I programs the board over the network. You only need to copy the `.bit` if you program from the lab PC with the Vivado Lab GUI instead.

---

## C. Server: Raspberry Pi firmware and SD-card files

The Pi runs a small bare-metal program (no Linux) that acts as the SPI slave. It is built from `software/rpi4_spi_slave/`.

**C.1 Build the program and download the Pi boot firmware** (the download needs internet):
```bash
make -C software/rpi4_spi_slave clean all sdcard firmware
ls -l software/rpi4_spi_slave/build/sdcard/
```

**C.2 Check that the folder contains exactly these 5 files, none of them 0 bytes:**

| File | Size (ours) | What it is |
|---|---|---|
| `start4.elf` | 2,305,632 (about 2.3 MB) | Pi boot firmware |
| `fixup4.dat` | 5,499 | Pi boot firmware |
| `bcm2711-rpi-4-b.dtb` | about 50–60 KB | Pi 4 device tree. **Required:** without it the Pi never starts our program (Part P, C2) |
| `config.txt` | about 0.8 KB | boot configuration (from `software/rpi4_spi_slave/config.txt`) |
| `kernel8.img` | 3,379 | our SPI-slave program |

If `bcm2711-rpi-4-b.dtb` is missing, your copy of the Makefile predates the fix. Download the file by hand:
```bash
curl -fL -o software/rpi4_spi_slave/build/sdcard/bcm2711-rpi-4-b.dtb \
  https://raw.githubusercontent.com/raspberrypi/firmware/stable/boot/bcm2711-rpi-4-b.dtb
```

**C.3 Optional: turn on the Pi firmware's boot log on the UART.** This is very useful the first time, and harmless afterwards:
```bash
echo "uart_2ndstage=1" >> software/rpi4_spi_slave/build/sdcard/config.txt
```

---

## D. Server: test programs

```bash
# boot_e2e.elf (self-checking test) + the second-stage ROM bootrom_ext.elf (for mode 1)
make -C source/final_tests/09_spi_boot_e2e streams RISCV_PREFIX=$RV
# factorial.elf
make -C software factorial.elf RISCV_PREFIX=$RV
ls -l source/final_tests/09_spi_boot_e2e/build/boot_e2e.elf software/build/bootrom_ext.elf software/factorial.elf
```
All three files must exist.
- If `streams` fails with `ERROR: source/uncore/rom_ahb.sv does not hold the SPI boot loader`, see A.5.
- If it fails with `No module named 'elftools'`, see A.4.

---

## E. Write the SD card

Use a microSD card with a **FAT32 first partition**. A card that already has Raspberry Pi OS works too: it shows two partitions, **bootfs** (FAT32) and **rootfs** (Linux). Only **bootfs** is used.

**Rules:**
- The 5 files from C.2 go **directly on the top level** of the FAT32 partition, **not inside a folder**.
- **Delete everything else** on that partition first. Keep a backup if the card had Raspberry Pi OS on it.
- **Never format or change rootfs.**

### E.1 From a Windows PC
1. Copy the files from the server. Open **PowerShell**:
   ```powershell
   cd $HOME\Downloads
   scp -r "<user>@vlsi-srv.iitbbs.ac.in:<REPO>/software/rpi4_spi_slave/build/sdcard" .
   dir sdcard
   ```
   Check the 5 sizes against C.2.

   If PowerShell says `scp is not recognized`, install **WinSCP**, connect to `vlsi-srv.iitbbs.ac.in`, and drag the `sdcard` folder across.
2. Insert the card. It appears as a drive, for example `E:` (named `bootfs` on a Pi OS card).
3. ⚠️ If Windows says **"You need to format the disk in drive F: before you can use it"**, click **Cancel**. That is the Linux partition. Formatting it is not needed and would erase it.
4. Copy the files, replacing `E:` with your drive letter:
   ```powershell
   Copy-Item $HOME\Downloads\sdcard\* E:\ -Force
   dir E:\
   ```
   `dir E:\` must show the 5 files with the sizes from C.2. **`start4.elf` must not be 0 bytes.**
5. In File Explorer, right-click the drive and choose **Eject**. Wait for "Safe to remove" before pulling the card.

### E.2 From a Linux PC
```bash
scp -r <user>@vlsi-srv.iitbbs.ac.in:<REPO>/software/rpi4_spi_slave/build/sdcard ~/sdcard
lsblk -o NAME,FSTYPE,SIZE,MOUNTPOINT      # find the card's vfat partition and its mount point
ls /media/$USER/                          # e.g. bootfs
cp ~/sdcard/* /media/$USER/bootfs/
ls -l /media/$USER/bootfs/                # 5 files, sizes as in C.2, nothing 0 bytes
sync
umount /media/$USER/bootfs /media/$USER/rootfs 2>/dev/null
```

Put the card into the Pi's microSD slot, on the underside of the board, at the end opposite the USB ports.

---

## F. Lab PC: one-time setup

Everything in this part is done once per lab PC.

**F.1 Python libraries:**
```bash
python3 -m pip install --user pyserial pyelftools
# or: sudo apt install python3-serial python3-pyelftools      (Ubuntu/Debian)
python3 -c "import serial, elftools; print('ok')"             # must print ok
```

**F.2 Serial-port permission.** Without this you get `Permission denied: '/dev/ttyUSB…'`. A udev rule lasts across re-plugs and reboots:
```bash
printf 'SUBSYSTEM=="tty", ATTRS{idVendor}=="1a86", MODE="0666"\nSUBSYSTEM=="tty", ATTRS{idVendor}=="0403", MODE="0666"\n' \
  | sudo tee /etc/udev/rules.d/99-bench-serial.rules
sudo udevadm control --reload-rules && sudo udevadm trigger
```
- `1a86` is the CH340 adapter and `0403` is the Basys's FTDI chip. If your adapter is different, add its vendor ID, which `lsusb` shows as `ID xxxx:yyyy`: `10c4` for CP210x, `067b` for PL2303.
- Alternatives:
  - `sudo usermod -aG dialout $USER`, then **log out and back in**;
  - for right now only: `sudo chmod a+rw /dev/ttyUSB*`. This is **lost on every re-plug**.

**F.3 hw_server and the cable drivers.** Install **Vivado Lab Solutions** (or Vivado) 2024.2. Then install the Digilent/Xilinx cable drivers once, as root, and re-plug the board afterwards:
```bash
sudo <Vivado_Lab install dir>/data/xicom/cable_drivers/lin64/install_script/install_drivers/install_drivers
```
Start hw_server and leave its terminal open whenever you program the board:
```bash
<Vivado_Lab install dir>/bin/hw_server        # prints "hw_server application started", listens on port 3121
```

**F.4 The lab PC's IP address:**
```bash
hostname -I
```
The FPGA Makefiles default to `10.10.92.226:3121`. If your address differs, add `HW_SERVER=<LABPC_IP>:3121` to every `stream_remote` command. The address can change after a reboot (DHCP).

---

## G. Lab PC: copy the bench files and create the helper scripts

**These files are not in the repository.** Every new bench needs them recreated.

**G.1 Copy the build outputs from the server into `~/bench`.** It asks for your password once:
```bash
mkdir -p ~/bench && cd ~/bench
ssh <user>@vlsi-srv.iitbbs.ac.in 'R=~/<REPO>; tar cf - \
  -C $R/software make_image.py factorial.elf \
  -C $R/software/build bootrom_ext.elf \
  -C $R/software/rpi4_spi_slave/host rpi4_cmd.py \
  -C $R/source/final_tests/09_spi_boot_e2e/build boot_e2e.elf' | tar xf -
ls ~/bench
```
Expect: `boot_e2e.elf  bootrom_ext.elf  factorial.elf  make_image.py  rpi4_cmd.py`.

If tar reports a missing file, build it on the server first (Part D).

**G.2 `dbg.py`, the debugger command sender.** Typing into a serial terminal (miniterm) did **not** reach the debugger on our bench, but a script works reliably. It sends each argument as one debugger command and prints the reply:
```bash
cat > ~/bench/dbg.py <<'EOF'
#!/usr/bin/env python3
"""dbg.py - send ADP debugger commands to the 1TOPS SoC and print the replies.
Usage: python3 dbg.py "A 80014000" "R" ...      Port: environment variable DBG."""
import os, sys, time
import serial
port = os.environ.get("DBG")
if not port:
    sys.exit("set DBG first, e.g.: export DBG=/dev/serial/by-id/usb-Digilent_...-if01-port0")
s = serial.Serial(port, 115200, timeout=0.3)
s.reset_input_buffer()
for c in sys.argv[1:]:
    s.write(c.encode() + b"\r"); s.flush()
    r, t = b"", time.time() + 2
    while time.time() < t and not r.endswith(b"]"):
        r += s.read(100)
    print(f"{c:12s} -> {r.decode(errors='replace').replace(chr(13), '').replace(chr(10), ' ').strip()}")
EOF
```

**G.3 `uart_probe.py`, a Pi UART diagnostic.** You only need it if the Pi doesn't answer. It captures the raw bytes while you power-cycle the Pi, then tries `STAT` at many baud rates:
```bash
cat > ~/bench/uart_probe.py <<'EOF'
import serial, sys, time
port = sys.argv[1]
print(">>> Unplug and re-plug the Pi power NOW (capturing 20 s)")
with serial.Serial(port, 115200, timeout=0.1) as s:
    buf, t = b"", time.time() + 20
    while time.time() < t:
        buf += s.read(4096)
i = buf.rfind(b"MESS:")
tail = buf[i:] if i >= 0 else buf
print(">>> bytes from the last MESS line on:", len(tail))
print(repr(tail[-300:]))
print(">>> scanning baud rates with STAT (about 90 s)")
b = 1200.0
while b < 2000000:
    try:
        with serial.Serial(port, int(b), timeout=0.25) as s:
            s.reset_input_buffer(); s.write(b"STAT"); s.flush()
            r = s.read(200)
        if r:
            print(f"  baud {int(b):8d}: {r!r}")
    except Exception as e:
        print(f"  baud {int(b):8d}: cannot set ({e})")
    b *= 1.03
print(">>> done")
EOF
```

**G.4 `ports.sh`, the port names.** Fill this in during Part J.

---

## H. Wiring

**Do all wiring with everything unplugged** (Section 2).

### H.1 The Pi 4 40-pin header (J8)
Hold the Pi with the USB and Ethernet ports pointing **right**. The 40-pin header then runs along the **top** edge.
- The **edge row** has the even pins: 2, 4, 6 and so on.
- The **inner row** has the odd pins: 1, 3, 5 and so on.
- **Pin 1** is at the **left end of the inner row**, the end away from the USB ports. On the underside of the board, its solder pad is square.

```
            ── board edge ──
 edge row:  2:5V!  4:5V!  6:GND  8:TXD  10:RXD  12     14:GND  16:GPIO23  18:GPIO24  20:GND  22:GPIO25 ...
 inner row: 1:3V3! 3      5      7      9:GND   11     13      15:GPIO22  17:3V3!    19      21        ...
            ↑ pin 1 end                                                    (USB/Ethernet ports this way →)
```
Count in pairs from the pin-1 end. Pins 7 and 8 are the 4th pair, pins 9 and 10 the 5th, pins 15 and 16 the 8th, pins 17 and 18 the 9th, pins 19 and 20 the 10th, and pins 21 and 22 the 11th.

### H.2 Basys 3 PMOD **JC** (SPI)
Use the connector labelled **JC**. It has 2 rows of 6 pins; use the **upper row** (pins 1–6), the row farther from the board surface.
- Pins 1–4 are signals.
- **Pin 5 is GND. Pin 6 is 3.3 V: never connect it.**
- **Pin 1 is at the opposite end from GND and VCC.**

If you aren't sure which end that is, measure with a multimeter (the Basys powered) between each end pin and Pi pin 6 (GND, through the common ground). The pin reading about 3.3 V is pin 6, and pin 5 sits right next to it.

### H.3 Wire table

| From | To | Signal | Notes |
|---|---|---|---|
| Basys **JC pin 1** | Pi **pin 18** (GPIO24) | CS (SoC → Pi) | Without it the Pi never sees a transfer: `SENT=0` and error E1 |
| Basys **JC pin 2** | Pi **pin 15** (GPIO22) | MOSI (SoC → Pi) | Not used by the protocol; wire it anyway |
| Basys **JC pin 3** | Pi **pin 16** (GPIO23) | MISO (Pi → SoC) | |
| Basys **JC pin 4** | Pi **pin 22** (GPIO25) | SCLK (SoC → Pi) | |
| Basys **JC pin 5** (GND) | Pi **pin 20** (GND) | Ground | **Required** |
| Adapter **GND** | Pi **pin 6** (GND) | Ground | **Required** |
| Adapter **RXD** | Pi **pin 8** (GPIO14 TXD) | Pi → PC | TX goes to RX |
| Adapter **TXD** | Pi **pin 10** (GPIO15 RXD) | PC → Pi | RX goes to TX |
| Adapter **VCC/5V/3V3** | **nothing** | | Never connect it |

### H.4 Cables and power
| Cable | Plug into | Other end |
|---|---|---|
| Basys micro-USB | Basys **J4 "PROG UART"**, with JP2 = USB | **lab PC** USB port. This one cable carries power, JTAG and the debugger UART |
| Adapter USB | | **lab PC** USB port |
| Pi USB-C supply | Pi USB-C **power** port | wall socket |

**Basys switches:**
- **SW0 (dbg_sel) DOWN.** If it's up, the debugger ignores the USB-UART, and LED1 is on.
- **SW1 (boot_mode) DOWN.** The SPI boot doesn't use it; it only sets a status bit.
- The **POWER switch** is ON.

**Power-up order:**
1. Insert the SD card into the Pi.
2. Plug in the Pi's power.
3. Plug in the Basys USB and switch the Basys on.
4. Plug the adapter into the lab PC.

---

## I. Program the FPGA

1. On the **lab PC**, check that `hw_server` is running (F.3) and that the Basys is on.
2. On the **server**, from the repo root:
   ```bash
   make -C fpga stream_remote                                  # if the lab PC is 10.10.92.226
   make -C fpga stream_remote HW_SERVER=<LABPC_IP>:3121         # otherwise
   ```
   A successful run prints:
   ```
   Using bitstream: .../fpga/output/tops_soc_basys3.bit (2192125 bytes, <date>)
   JTAG targets seen by hw_server <ip>:3121: <ip>:3121/xilinx_tcf/Digilent/210183AA0B8DA
   INFO: [Labtools 27-3164] End of startup status: HIGH
   PROGRAM OK: xc7a35t_0 <- .../tops_soc_basys3.bit
   ```
   The Basys **DONE** LED comes on.

   Also normal: `...programmed with a design that has no supported debug core(s)`. This design has no ILA.

The FPGA keeps its configuration until power-off. **Reprogram after every power cycle of the Basys.**

---

## J. Find the serial ports

On the **lab PC**, with the Basys and the adapter plugged in:
```bash
ls -l /dev/serial/by-id/
```
Ours:
```
usb-1a86_USB_Serial-if00-port0 -> ../../ttyUSB0                                ← USB-UART adapter (Pi)
usb-Digilent_Digilent_USB_Device_210183AA0B8D-if01-port0 -> ../../ttyUSB1       ← Basys debugger UART
```
- The **Basys** line contains `Digilent` and ends in **`-if01-port0`**. Interface 00 is the JTAG.
- The **adapter** is the other line: `1a86` for CH340, `Silicon_Labs`/`CP210x`, `Prolific` or `FTDI`.
- If you're unsure, unplug the adapter and run `ls` again: the line that disappears is the adapter.

**Always use the `/dev/serial/by-id/...` names, never `ttyUSBn`.** The `n` numbers change when you re-plug; the by-id names stay the same.

Create `~/bench/ports.sh` with your two names:
```bash
cat > ~/bench/ports.sh <<'EOF'
export DBG=/dev/serial/by-id/usb-Digilent_Digilent_USB_Device_210183AA0B8D-if01-port0
export PI=/dev/serial/by-id/usb-1a86_USB_Serial-if00-port0
EOF
```
Every new terminal must load it first:
```bash
cd ~/bench && source ports.sh && echo "$DBG $PI"
```

---

## K. Bring-up checks

Do these in order: each check depends on the previous one.

**K.1 The Pi boots and prints its banner.** Run the command below, then power-cycle the Pi:
```bash
python3 -m serial.tools.miniterm $PI 115200
```
- With `uart_2ndstage=1` (C.3), the firmware log (`MESS:` lines) appears first.
- Then this line appears:
  ```
  RPI4-SPI-SLAVE ready: SPI mode 3 slave, CS=GPIO24 SCLK=GPIO25 MISO=GPIO23; send PICO+len+stream (make_image.py --serial)
  ```
- The Pi's **green LED ends up OFF**.

Quit with **Ctrl+]**. Only one program can use a port at a time.

**K.2 The Pi answers commands:**
```bash
python3 rpi4_cmd.py --serial $PI STAT
python3 rpi4_cmd.py --serial $PI TIME
```
Ours:
```
ARMED=0 SENT=0 REM=0
TIME gplev0_read_ns=12 gpio_write_ns=5 loop_ns=74 worst_reaction_ns=79 budget_ns=2000 margin=OK
```
`margin=OK` means the Pi reacts to SPI edges with plenty of margin: 79 ns at worst against a 2000 ns budget.

**K.3 The debugger answers.** Press **btnC** on the Basys, then run:
```bash
python3 dbg.py "A 80010000" "R"
```
Expect `A 80010000 -> A 0x80010000 ]`, then `R -> R 0x........ ]`. The value can be anything.

**K.4 Optional: check that the SoC drives SPI without a stream.** With the Pi not armed (`ARMED=0`), press btnC, then run:
```bash
python3 dbg.py "A 80017FFC" "R"
```
Expect `R 0x000000e1`: error E1, no valid stream. This proves the CPU ran the boot ROM and that the ROM tried SPI.

---

## L. Test 1: boot_e2e (mode 0 and mode 1)

`boot_e2e.elf` checks itself. It has code plus an expected-values table in instruction RAM, and the same table as initialised data in data RAM. It writes **`0x600DB007` to `0x8001_4000`** only if both chunks arrived intact. If they didn't, it writes `0xBAD0_00ii` there.

### L.1 Mode 0
```bash
cd ~/bench && source ports.sh
# 1. clear the result words (RAM survives btnC, so an old PASS could fool you)
python3 dbg.py "A 80014000" "W 00000000" "A 80017FFC" "W 00000000"
# 2. store the stream in the Pi -> green LED turns ON
python3 make_image.py --mode 0 --test boot_e2e.elf --serial $PI
```
Expect:
```
wrote flash.bin: 248 bytes (mode 0)
sent 256 bytes to the SPI slave on /dev/serial/by-id/usb-1a86_USB_Serial-if00-port0 @ 115200: b'OK'
```
3. **Press btnC.** The Pi's green LED turns **OFF** once the whole stream has been sent.
4. Read the results:
   ```bash
   python3 dbg.py "A 80014000" "R" "A 80017FFC" "R"
   python3 rpi4_cmd.py --serial $PI STAT
   ```
   Expect (ours):
   ```
   A 80014000   -> A 0x80014000 ]
   R            -> R 0x600db007 ]        ← test passed
   A 80017FFC   -> A 0x80017ffc ]
   R            -> R 0x00000000 ]        ← no boot error
   ARMED=248 SENT=248 REM=0              ← the Pi sent everything
   ```

### L.2 Mode 1 (through the second-stage ROM)
```bash
python3 dbg.py "A 80014000" "W 00000000" "A 80017FFC" "W 00000000"
python3 make_image.py --mode 1 --test boot_e2e.elf --ext bootrom_ext.elf --serial $PI
```
Expect `wrote flash.bin: 620 bytes (mode 1)` and `sent 628 bytes ... b'OK'`.

**Press btnC**, then:
```bash
python3 dbg.py "A 80014000" "R" "A 80017FFC" "R"
python3 rpi4_cmd.py --serial $PI STAT
```
Expect `R 0x600db007`, `R 0x00000000` and `ARMED=620 SENT=620 REM=0`.

### L.3 Repeatability (5 runs)
```bash
for i in 1 2 3 4 5; do
  python3 dbg.py "A 80014000" "W 00000000" "A 80017FFC" "W 00000000" >/dev/null
  python3 make_image.py --mode 1 --test boot_e2e.elf --ext bootrom_ext.elf --serial $PI | tail -1
  read -p "run $i: press btnC, then press Enter here " _
  python3 dbg.py "A 80014000" "R" "A 80017FFC" "R" | grep "^R"
  python3 rpi4_cmd.py --serial $PI STAT
done
```
Every run must show `R 0x600db007`, `R 0x00000000` and `SENT=620 REM=0`.

For mode 0, use `--mode 0 --test boot_e2e.elf`, without `--ext`.

**Negative control:** pressing Enter **without** btnC gives `R 0x00000000`, `R 0x00000000` and `ARMED=620 SENT=0 REM=620`. Nothing ran, which proves the pass word comes from a real boot. We saw exactly this.

---

## M. Test 2: factorial

`software/factorial.S` reads **n from `0x8001_0000`** and writes **n! to `0x8001_0004`**. It has no data section, so the boot doesn't overwrite `0x8001_0000`: you set n with the debugger before pressing btnC.
```bash
cd ~/bench && source ports.sh
python3 dbg.py "A 80010000" "W 00000005" "W 00000000"     # n = 5, clear the result (W steps the address by 4)
python3 make_image.py --mode 0 --test factorial.elf --serial $PI
```
Expect `wrote flash.bin: 96 bytes (mode 0)` and `... b'OK'`.

**Press btnC**, then:
```bash
python3 dbg.py "A 80010000" "R" "R"
```
Expect `R 0x00000005` (n), then `R 0x00000078` (120 = 5!).

| n | first `W` value | expected result |
|---|---|---|
| 5 | `00000005` | `0x00000078` (120) |
| 10 | `0000000a` | `0x00375f00` (3628800) |
| 12 | `0000000c` | `0x1c8cfc00` (479001600) |
| 13 | `0000000d` | `0x7328cc00` (13! wraps around 32 bits) |

⚠️ Addresses always have **8 hex digits**. `A 8001000` (7 digits) sets the address to `0x08001000`, which is the wrong place. We made this mistake once: the result read `0x00000001`, which meant nothing.

For mode 1, add `--ext bootrom_ext.elf` to the `make_image.py` line.

---

## N. Booting your own program

Any RV32I program works if:
- it is **linked with `software/link.ld`**: code and read-only data in instruction RAM at `0x8000_0000` (32 KB), and data in data RAM at `0x8001_0000` (32 KB);
- in **mode 1**, it stays below `0x8000_7C00`, because the second-stage ROM sits in the top 1 KB of instruction RAM;
- it leaves the top of data RAM alone: `0x8001_7FFC` is the boot error word, and the loader's stack starts at `0x8001_8000`;
- it doesn't rely on zeroed RAM. `.bss` is not part of the stream, and RAM keeps old contents across btnC, so clear it in your own start-up code.

Build it, for example: `$(RV)gcc -march=rv32i -mabi=ilp32 -nostdlib -nostartfiles -T software/link.ld prog.S -o prog.elf`. Copy `prog.elf` to `~/bench`, then:
```bash
python3 make_image.py --mode 0 --test prog.elf --serial $PI --dump    # --dump lists the chunks
```
Press btnC, then read your result addresses with `dbg.py`. `make_image.py` refuses chunks outside the two RAMs (`chunk ... outside IMEM/DMEM`).

---

## O. Daily quick start

Once everything has been set up:
1. Power on the Pi first, then the Basys. On the lab PC, start `hw_server`.
2. On the server, run `make -C fpga stream_remote [HW_SERVER=<LABPC_IP>:3121]` and wait for `PROGRAM OK`.
3. On the lab PC, run `cd ~/bench && source ports.sh`.
4. Run `python3 rpi4_cmd.py --serial $PI STAT`. It should reply `ARMED=...`.
5. Run a test (Part L or M): clear → `make_image.py` → **btnC** → read.

---

## P. Troubleshooting: every error we hit

Each entry lists: **condition** (what causes it), **signature** (what you see), and **fix / prevention**.

### Building on the server

| # | Condition | Signature | Fix / prevention |
|---|---|---|---|
| B1 | The boot ROM RTL is not the SPI loader | Suite 09: `ERROR: source/uncore/rom_ahb.sv does not hold the SPI boot loader.` On hardware: the old test ROM runs instead, nothing is loaded from the Pi (`STAT` stays `SENT=0`) | A.5: `make -C software rom RISCV_PREFIX=$RV`, then rebuild the bitstream (B.2) |
| B2 | The ZCU102 clock input goes straight into the MMCM | Vivado: `[Place 30-681] Sub-optimal placement for a global clock-capable IO pin and MMCM pair` | Fixed in the repo: `IBUFDS → BUFG → MMCM` in `fpga/zcu102/top/tops_soc_zcu102_top.sv`. Use the current top |
| B3 | An old `ram_ahb.sv` capped the RAMs at 64 words under any `SYNTHESIS` define (and Vivado defines it) | Synthesis log shows the RAMs with `depth=64`; programs larger than 256 B corrupt | Fixed: the cap now applies only under `SOC_LINT_SMALL_RAM`. Use the current `source/uncore/ram_ahb.sv` |
| B4 | Timing not met | `Timing NOT met (WNS …, WHS …)`, build stops | Check `fpga/output/timing_summary.rpt`. Don't use a failing bitstream on the bench |
| B5 | pyelftools missing | `ModuleNotFoundError: No module named 'elftools'` | A.4 |
| B6 | Wrong or missing `RISCV_PREFIX` | `riscv64-unknown-elf-gcc: command not found` (or `No such file or directory`) | A.2: set `RV` and pass `RISCV_PREFIX=$RV` |
| B7 | `aarch64-none-elf-gcc` not on PATH | `aarch64-none-elf-gcc: command not found` (or `No such file or directory`) | A.3 |
| B8 | No internet on the server during `make firmware` | `curl: (6) Could not resolve host` | Download `start4.elf`, `fixup4.dat` and `bcm2711-rpi-4-b.dtb` elsewhere from `https://raw.githubusercontent.com/raspberrypi/firmware/stable/boot/` |

### Programming the FPGA (`make -C fpga stream_remote`)

| # | Condition | Signature | Fix / prevention |
|---|---|---|---|
| P1 | hw_server not running, wrong IP (DHCP), or port 3121 blocked | Error while connecting to `TCP:<ip>:3121` | Start hw_server (F.3); check `hostname -I` (F.4); pass `HW_SERVER=<ip>:3121` |
| P2 | hw_server runs but sees no board: Basys off, cable not in J4, charge-only cable, no cable drivers, or another program (Adept, WaveForms, a local Hardware Manager) holding the cable | Current script: `JTAG targets seen by hw_server ...: NONE` plus a checklist. Older script: `ERROR: [Labtoolstcl 44-469] There is no current hw_target.` | Power on (the power LED is lit); use a data cable in J4; install the drivers (F.3); close other tools; restart hw_server |
| P3 | Older `fpga/hw_program.tcl` checked a DONE property that doesn't exist on the Artix-7 | `ERROR: [Labtoolstcl 44-56] hw_device [xc7a35t_0] does not have a [REGISTER.IR.BIT05_DONE] property` **after** `End of startup status: HIGH` | **Programming actually succeeded** (DONE LED on). Fixed in the current script, which prints `PROGRAM OK` |

### Raspberry Pi and SD card

| # | Condition | Signature | Fix / prevention |
|---|---|---|---|
| C1 | `start4.elf` on the card is **0 bytes** (a failed or partial copy) | Green LED **blinks about 3 times, then stays solidly ON**; nothing at all on the UART | Recopy and check the sizes (C.2/E). Never trust a copy without `ls -l` / `dir` |
| C2 | **`bcm2711-rpi-4-b.dtb` missing** from the card | Firmware log: `dterror: Failed to load Device Tree file '?'`, then `Loaded 'kernel8.img' to 0x80000` and nothing after (last line cut off as `MESS:...:0:`). No banner; `STAT` → `no reply`. **The green LED goes OFF, which is misleading**: the firmware does that, not our program | Put the `.dtb` on the card (C.2). Since it was added, everything works |
| C3 | Files inside a folder on the card, or the card not FAT32 | The Pi doesn't boot: the green LED blinks a repeating error pattern, nothing on the UART | Files at the top level of the FAT32 partition (E) |
| C4 | Formatting the second (rootfs) partition when Windows asks | (data loss) | Click **Cancel** (E.1) |
| C5 | Unsure whether the Pi program runs at all | – | Optional: `make -C software/rpi4_spi_slave diag` builds `build/diag/kernel8.img`. Put it on the card in place of `kernel8.img`. It prints `DIAG A/B/C` lines in a loop (mini UART, PL011 with the firmware's settings, PL011 with our settings), and the LED blinks every 3 s. Put the real `kernel8.img` back afterwards |

### Serial ports on the lab PC

| # | Condition | Signature | Fix / prevention |
|---|---|---|---|
| S1 | No permission on the port (also after **every re-plug** if you used `chmod`) | `PermissionError: [Errno 13] Permission denied: '/dev/serial/by-id/...'` | udev rule (F.2) |
| S2 | Typo in `chmod` | `chmod: cannot access '/dev/tty/USB1': Not a directory` | It's `/dev/ttyUSB1`, with no slash before `USB` |
| S3 | Port already open in another program (miniterm still running) | `Device or resource busy` / `could not open port` | Close the other program (Ctrl+] in miniterm). `sudo fuser -v /dev/ttyUSB*` shows who holds it |
| S4 | `$PI` / `$DBG` not set in this terminal | `--serial` errors, or dbg.py: `set DBG first` | `cd ~/bench && source ports.sh` in **every** new terminal |
| S5 | Wrong command for the tool | `rpi4_cmd.py: error: argument command: invalid choice: '115200'` | `rpi4_cmd.py` only takes `STAT` or `TIME`. The terminal is `python3 -m serial.tools.miniterm $PI 115200` |
| S6 | Typing in miniterm doesn't reach the debugger (our bench) | Banner visible after btnC, but no reply to typed commands, and LED15 doesn't light | Use `dbg.py` (G.2). It sends complete commands, ending in CR |
| S7 | Address with 7 instead of 8 hex digits | `A 8001000 -> A 0x08001000` | Always 8 digits (`80010000`) |
| S8 | In a terminal, typing `X` or `B ...` into the debugger | `X` leaves command mode; `B` changes the debugger baud rate | Don't. If the prompt stops answering, send `Esc` (0x1B), or press btnC |

### `rpi4_cmd.py` / `make_image.py` replies

| # | Condition | Signature | Fix / prevention |
|---|---|---|---|
| R1 | The Pi didn't boot (C1–C3), TX and RX swapped, adapter GND missing, or a wrong adapter port | `no reply (check wiring/baud, and that the Pi program is running)` | Check K.1 first (banner). Swap the wires on pins 8 and 10. Wire GND to pin 6. If needed, test the adapter alone: bridge its TXD to its RXD and type in miniterm; the letters must echo. Run `uart_probe.py` (G.3) |
| R2 | The stream has length 0 or is too large (> 96 KB) | `make_image.py` reply `b'E2'` | Smaller program; check `--dump` |
| R3 | The serial transfer stopped part-way | `make_image.py` reply `b'E3'` | Rerun; check the adapter cable and port |

### Boot results (read with `dbg.py`)

| # | Condition | Signature | Fix / prevention |
|---|---|---|---|
| E1a | btnC pressed but the Pi **not armed**: you forgot `make_image.py`, or pressed btnC twice. A SoC reset never rewinds the Pi | `80017FFC = 0x000000e1`; `STAT` shows `ARMED=0`, or `REM=0` from the previous boot | Run `make_image.py` before **every** btnC |
| E1b | Armed, but **the Pi never saw the transfer**: CS wire (JC1 → pin 18) off, SCLK wire wrong, or no GND between the boards | `80017FFC = 0x000000e1`; `STAT` shows `SENT=0 REM=<all>`; the Pi's green LED stays **ON** after btnC | Recheck H.3, especially CS on pin 18 and GND on pin 20. In our case the CS wire had been left off after a test |
| E1c | Reset during a load (btnC pressed twice quickly) | E1, with `STAT` showing `0 < SENT < ARMED` | Re-arm with `make_image.py`, then press btnC once |
| E2 | A chunk outside instruction/data RAM | `80017FFC = 0x000000e2` | Link with `software/link.ld` (Part N) |
| N1 | **btnC not pressed** | Both words still `0x00000000`; `STAT` shows `SENT=0 REM=<all>`; the green LED stays on | Press btnC |
| N2 | The data arrived corrupted | `80017FFC = 0`, but `80014000 = 0xBAD0_00ii` (boot_e2e) | Check the wiring and GND; run `TIME` (margin must be OK); rerun |
| N3 | Debugger banner missing after btnC | No `0x50c1ab04` | `$DBG` must be the **Digilent if01** port; SW0 must be down (LED1 off); the FPGA must be programmed (DONE LED) |

---

## Q. ZCU102 (next board, not yet bench-verified)

The SoC, the stream, the Pi side and the tests are the same; only the board connections change. Source: `fpga/zcu102/README.md`.

| | Basys 3 | ZCU102 |
|---|---|---|
| Power | USB (J4) | **Its own 12 V supply and power switch only.** No other source |
| Boot-mode switch | – | **SW6 = JTAG** (`SW6[4:1]` = on, on, on, on) |
| JTAG to the hw_server PC | J4 (same cable as power) | micro-USB **J2** |
| Debugger UART | J4 (Digilent if01) | micro-USB **J83** (CP2108: 4 serial ports; the debugger is on channel 2. Find it by trying `dbg.py "A 80010000"` on each `/dev/serial/by-id/...CP2108...` port) |
| Reset (btnC) | btnC | **SW20 CPU_RESET** |
| dbg_sel | SW0 down | **SW13 position 1** off |
| SPI to the Pi | PMOD JC 1/2/3/4 + GND | PMOD0 **J55.1** (CS) / **J55.3** (MOSI) / **J55.5** (MISO) / **J55.7** (SCLK), plus a J55 **GND** pin (see UG1182 Figure 3-28; never the 3.3 V pins) |
| "Debugger UART RX" LED | LED15 | LED2. LED4 means clock OK, LED7 is the heartbeat |

**Build and program, on the server:**
```bash
nohup make -C fpga/zcu102 build_fpga > nohup_zcu.out 2>&1 &
grep -E "Timing: WNS|ERROR" nohup_zcu.out               # our last build: WNS = 6.396 ns, WHS = 0.020 ns
make -C fpga/zcu102 stream_remote [HW_SERVER=<LABPC_IP>:3121]
```
`fpga/zcu102/hw_server.tcl` still opens the JTAG target without first listing the targets. So "no board seen" shows as the old `There is no current hw_target` message, which means the same as P2.

Then follow Parts J–M with `DBG` set to the ZCU102 debugger port, pressing SW20 instead of btnC.

---

## R. Reference

### Memory map (used by the tests)
| Address | What |
|---|---|
| `0x0000_1000` | Internal boot ROM (first fetch after btnC) |
| `0x8000_0000 – 0x8000_7FFF` | Instruction RAM (32 KB). Mode 1: the second-stage ROM at `0x8000_7C00 – 0x8000_7FFF` |
| `0x8001_0000 – 0x8001_7FFF` | Data RAM (32 KB) |
| `0x8001_0000` / `0x8001_0004` | factorial: n / result |
| `0x8001_4000` | boot_e2e: `0x600DB007` = PASS, `0xBAD0_00ii` = FAIL |
| `0x8001_7FFC` | Boot error word: `0xE1` = bad magic (no or garbled stream), `0xE2` = chunk outside RAM |

### Debugger (ADP) commands used
| Command | Meaning | Reply |
|---|---|---|
| `A 8001xxxx` | Set the address (8 hex digits) | `A 0x8001xxxx` |
| `W 0000abcd` | Write a word, then address += 4 | `W 0x0000abcd` |
| `R` | Read a word, then address += 4 | `R 0x........` |
| `C 0202` / `C 0102` | Halt / resume the core (LED0) | |

The banner after reset is ` 0x50c1ab04`, and the prompt is `]`. Full list: `source/debugger/COMMANDS.md`.

### Pi serial protocol (115200 8N1)
| Host sends | Pi replies |
|---|---|
| `PICO` + 4-byte length + stream (done by `make_image.py --serial`) | `OK`; `E2` = bad length; `E3` = timeout |
| `STAT` | `ARMED=<len> SENT=<bytes clocked out> REM=<left>` |
| `TIME` | Timing report, ending in `margin=OK` |

Rule: **only a new `make_image.py` rewinds the Pi to byte 0.** A SoC reset doesn't.

### LEDs
| LED | On | Off |
|---|---|---|
| Pi green (ACT) | A stream is armed and not yet fully sent | Nothing armed, or everything sent |
| Basys DONE | FPGA programmed | Not programmed |
| Basys LED0 | Core halted | Running |
| Basys LED1 | SW0 up (debugger on FT1248, not on the USB-UART) | SW0 down (normal) |

### Files created on the lab PC (not in the repo)
| File | Made in |
|---|---|
| `~/bench/{make_image.py, rpi4_cmd.py, boot_e2e.elf, bootrom_ext.elf, factorial.elf}` | G.1 (copied from the server) |
| `~/bench/dbg.py` | G.2 |
| `~/bench/uart_probe.py` | G.3 |
| `~/bench/ports.sh` | J |
| `/etc/udev/rules.d/99-bench-serial.rules` | F.2 |
