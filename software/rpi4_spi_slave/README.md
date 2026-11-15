# Raspberry Pi 4 bare-metal SPI-slave boot server (replaces the Pico)

The Pi 4 serves the boot stream to the 1TOPS SoC exactly as the Pico did. The SoC is the SPI master (mode 3), and the
Pi runs a bare-metal program (no Linux) that bit-bangs the SPI slave on GPIO.

Design, rationale and the full flow: **`rpi4_spi_boot_options.txt`** (repo root), sections 4 and 11.

## Wiring (3.3 V on both sides; common GND is required)
| Signal | SoC: Basys 3 / ZCU102 | Pi 4 GPIO (header pin) |
|---|---|---|
| CS (SoC → Pi) | JC1 K17 / J55.1 | GPIO 24 (pin 18) |
| MOSI (SoC → Pi, unused) | JC2 M18 / J55.3 | GPIO 22 (pin 15) |
| MISO (Pi → SoC) | JC3 N17 / J55.5 | GPIO 23 (pin 16) |
| SCLK (SoC → Pi) | JC4 P18 / J55.7 | GPIO 25 (pin 22) |
| GND | PMOD GND | pin 20 or 25 |

**Host link:** a 3.3 V USB-UART adapter on the laptop, connected to Pi GPIO 14 TXD (pin 8) → adapter RX, GPIO 15 RXD
(pin 10) ← adapter TX, plus GND. 115200 8N1.

## Build (server)
```bash
make              # build/kernel8.img   (CROSS=aarch64-none-elf- by default; or CROSS=aarch64-linux-gnu-)
make sdcard       # build/sdcard/ = config.txt + kernel8.img
make firmware     # adds start4.elf + fixup4.dat + bcm2711-rpi-4-b.dtb (or copy them from any Raspberry Pi OS boot partition)
make test         # host unit tests (no Pi needed)
```
SoC side: the boot ROM must be rebuilt with the 250 kHz SPI clock (`software/common/loader.S`, `SCKDIV_VAL 99`):
`make -C software rom`, then rebuild the FPGA.

## Use (bench)
1. Copy `build/sdcard/*` to the FAT32 boot partition of an SD card and boot the Pi. The terminal shows the
   `RPI4-SPI-SLAVE ready` banner.
2. Load a stream: `python3 software/make_image.py --mode 0 --test software/step_test.elf --serial /dev/ttyUSB0`.
   Expect `b'OK'`. The green ACT LED turns on (armed).
3. Reset the SoC (Basys btnC / ZCU102 SW20). The boot ROM pulls the stream, and the ACT LED turns off once it has all
   been sent.
4. To boot again, repeat steps 2 and 3. A SoC reset does not rewind the Pi (rule R4).

Diagnostics:
- `python3 host/rpi4_cmd.py --serial /dev/ttyUSB0 STAT` reports bytes armed / sent.
- `... TIME` measures the Pi's loop speed. It must report `margin=OK`.

Only send commands while the SoC is not booting.
