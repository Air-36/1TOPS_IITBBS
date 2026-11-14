#!/usr/bin/env python3
"""make_bad_stream.py - corrupt streams for scenario s4 of 09_spi_boot_e2e (loader bounds check).

Takes a valid stream from make_image.py and rewrites the header of its FIRST chunk so that the
boot loader must reject it with error 0xE2 before copying anything. make_image.py refuses to
build such streams, which is why they are patched here. One stream per rejection rule:

  gap       address 0x8000_8000: the unmapped gap between instruction RAM and data RAM
  below     address 0x7FFF_FF00: below instruction RAM
  above     address 0x8001_8000: above data RAM
  iram_end  address 0x8000_7FF0: starts in instruction RAM but runs past its end
  dram_end  address 0x8001_7FF0: starts in data RAM but runs past its end
  oversize  size 0x8001: larger than a RAM window (address unchanged)

Usage: make_bad_stream.py <good.bin> <bad.bin> [kind]      (kind defaults to gap)
"""
import struct
import sys

KINDS = {
    "gap":      (0x80008000, None),
    "below":    (0x7FFFFF00, None),
    "above":    (0x80018000, None),
    "iram_end": (0x80007FF0, None),
    "dram_end": (0x80017FF0, None),
    "oversize": (None, 0x8001),
}


def main():
    if len(sys.argv) not in (3, 4):
        sys.exit(__doc__)
    kind = sys.argv[3] if len(sys.argv) == 4 else "gap"
    if kind not in KINDS:
        sys.exit(f"unknown kind {kind!r}; choose one of {', '.join(KINDS)}")
    data = bytearray(open(sys.argv[1], "rb").read())
    if len(data) < 12 or data[:4] != b"BOOT":
        sys.exit(f"{sys.argv[1]}: not a boot stream (no 'BOOT' magic)")
    addr, size = struct.unpack_from("<II", data, 4)
    if size == 0:
        sys.exit(f"{sys.argv[1]}: first record is the end marker; no chunk to corrupt")
    new_addr, new_size = KINDS[kind]
    new_addr = addr if new_addr is None else new_addr
    new_size = size if new_size is None else new_size
    if kind in ("iram_end", "dram_end") and new_addr + new_size <= (new_addr & ~0x7FFF) + 0x8000:
        sys.exit(f"{kind}: chunk size {size:#x} too small to cross the window end")
    struct.pack_into("<II", data, 4, new_addr, new_size)
    open(sys.argv[2], "wb").write(data)
    print(f"wrote {sys.argv[2]} ({kind}): first chunk {addr:#010x}+{size:#x} -> {new_addr:#010x}+{new_size:#x}")


if __name__ == "__main__":
    main()
