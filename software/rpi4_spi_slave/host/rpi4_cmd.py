#!/usr/bin/env python3
"""rpi4_cmd.py - send a diagnostic command to the Raspberry Pi 4 SPI-slave program.

  python3 rpi4_cmd.py --serial /dev/ttyUSB0 STAT   ->  ARMED=<len> SENT=<bytes clocked out> REM=<left>
  python3 rpi4_cmd.py --serial /dev/ttyUSB0 TIME   ->  GPIO/loop timing measured on the Pi

Loading a boot stream is done with make_image.py ... --serial PORT (same protocol as the Pico).
Only send commands while the SoC is NOT booting (the Pi serves commands while CS is high).
Needs pyserial (pip install pyserial).
"""
import argparse
import sys
import time


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--serial", required=True, help="USB-UART adapter connected to Pi GPIO14/15")
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("command", choices=["STAT", "TIME"])
    a = ap.parse_args()

    import serial
    with serial.Serial(a.serial, a.baud, timeout=0.2) as s:
        s.reset_input_buffer()
        s.write(a.command.encode())
        s.flush()
        reply, t_end = b"", time.time() + 3.0     # TIME takes well under a second on the Pi
        while time.time() < t_end and not reply.endswith(b"\n"):
            reply += s.read(256)
    if not reply:
        sys.exit("no reply (check wiring/baud, and that the Pi program is running)")
    print(reply.decode(errors="replace").strip())


if __name__ == "__main__":
    main()
