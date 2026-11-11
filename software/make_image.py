#!/usr/bin/env python3
"""make_image.py - build the SPI boot stream from ELF files.

Image (per ELF):  "BOOT" | {addr,size,bytes}* | {entry,0}     (all words little-endian)
Stream:  mode 0 -> [test image]
         mode 1 -> [ext boot ROM image][test image]

Usage:
  make_image.py --mode 1 --test test.elf --ext bootrom_ext.elf -o flash.bin [--dump] [--serial /dev/ttyACM0]
"""
import argparse, struct, sys
from elftools.elf.elffile import ELFFile

IMEM = (0x80000000, 0x80008000)   # 32 KB instruction RAM (riscv_soc_ahb.v IRAM_BASE/SIZE)
DMEM = (0x80010000, 0x80018000)   # 32 KB data RAM        (riscv_soc_ahb.v DRAM_BASE/SIZE)
EXT_BASE = 0x80007C00             # top 1 KB of IMEM; must match bootrom_ext.ld
MAGIC = b"BOOT"


def build_image(path, dump=False):
    out = bytearray(MAGIC)
    chunks = []
    with open(path, "rb") as f:
        elf = ELFFile(f)
        entry = elf["e_entry"]
        for seg in elf.iter_segments():
            if seg["p_type"] != "PT_LOAD" or seg["p_filesz"] == 0:
                continue
            # skip header-only segments (lld maps the ELF header as a read-only LOAD at offset 0)
            if seg["p_offset"] == 0 and not (seg["p_flags"] & 0x3):   # no X, no W
                continue
            addr, size = seg["p_paddr"], seg["p_filesz"]   # p_filesz, not p_memsz
            end = addr + size
            if not ((IMEM[0] <= addr and end <= IMEM[1]) or (DMEM[0] <= addr and end <= DMEM[1])):
                sys.exit(f"{path}: chunk {addr:#x}+{size:#x} outside IMEM/DMEM")
            data = seg.data()
            out += struct.pack("<II", addr, size) + data
            chunks.append((addr, size, seg["p_memsz"]))
    out += struct.pack("<II", entry, 0)
    if dump:
        print(f"== {path}  entry={entry:#010x}  image={len(out)} bytes")
        for a, s, m in chunks:
            print(f"   LOAD addr={a:#010x} filesz={s:#x} memsz={m:#x}")
    return bytes(out), chunks, entry


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", type=int, choices=[0, 1], required=True)
    ap.add_argument("--test", required=True)
    ap.add_argument("--ext")
    ap.add_argument("-o", "--out", default="flash.bin")
    ap.add_argument("--dump", action="store_true")
    ap.add_argument("--serial")
    a = ap.parse_args()

    test, tchunks, _ = build_image(a.test, a.dump)
    stream = test
    if a.mode == 1:
        if not a.ext:
            sys.exit("mode 1 needs --ext")
        ext, echunks, eentry = build_image(a.ext, a.dump)
        if eentry < EXT_BASE:
            sys.exit("ext boot ROM entry below EXT_BASE")
        for addr, size, _ in tchunks:   # test must not overwrite the running ext boot ROM
            if addr < EXT_BASE + 0x400 and addr + size > EXT_BASE:
                sys.exit("test image overlaps external boot ROM region")
        stream = ext + test

    open(a.out, "wb").write(stream)
    print(f"wrote {a.out}: {len(stream)} bytes (mode {a.mode})")

    if a.serial:
        import serial
        with serial.Serial(a.serial, 115200, timeout=2) as s:
            s.write(b"PICO" + struct.pack("<I", len(stream)) + stream)
            print("sent to Pico:", s.read(2))   # Pico replies "OK"


if __name__ == "__main__":
    main()