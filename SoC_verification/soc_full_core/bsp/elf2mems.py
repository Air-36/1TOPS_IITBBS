#!/usr/bin/env python3
"""
elf2mems.py - Converts RISC-V 32-bit ELF into Verilog $readmemh memory images
for 1TOPS SoC IRAM (0x80000000) and DRAM (0x80010000).
"""

import sys
import struct

def parse_elf(elf_path, iram_size=32768, dram_size=32768):
    with open(elf_path, "rb") as f:
        elf = f.read()

    # Verify ELF Magic: \x7f E L F
    if elf[:4] != b'\x7fELF':
        raise ValueError(f"Invalid ELF magic in {elf_path}")

    ei_class = elf[4]   # 1 = 32-bit, 2 = 64-bit
    ei_data  = elf[5]   # 1 = Little Endian
    if ei_class != 1 or ei_data != 1:
        raise ValueError("Only 32-bit Little Endian ELF supported")

    # Read e_phoff, e_phentsize, e_phnum from 32-bit ELF Header
    e_phoff = struct.unpack_from('<I', elf, 28)[0]
    e_phentsize = struct.unpack_from('<H', elf, 42)[0]
    e_phnum = struct.unpack_from('<H', elf, 44)[0]

    iram = bytearray(iram_size)
    dram = bytearray(dram_size)

    # Parse Program Headers (PT_LOAD segments)
    for i in range(e_phnum):
        ph_offset = e_phoff + i * e_phentsize
        p_type = struct.unpack_from('<I', elf, ph_offset)[0]
        p_offset = struct.unpack_from('<I', elf, ph_offset + 4)[0]
        p_vaddr = struct.unpack_from('<I', elf, ph_offset + 8)[0]
        p_paddr = struct.unpack_from('<I', elf, ph_offset + 12)[0]
        p_filesz = struct.unpack_from('<I', elf, ph_offset + 16)[0]
        p_memsz = struct.unpack_from('<I', elf, ph_offset + 20)[0]

        if p_type != 1 or p_filesz == 0:  # PT_LOAD = 1
            continue

        seg_data = elf[p_offset : p_offset + p_filesz]
        addr = p_paddr if p_paddr != 0 else p_vaddr

        # Check IRAM aperture (0x8000_0000 - 0x8000_7FFF)
        if 0x80000000 <= addr < 0x80000000 + iram_size:
            rel = addr - 0x80000000
            end = min(rel + p_filesz, iram_size)
            iram[rel:end] = seg_data[:end-rel]
        # Check DRAM aperture (0x8001_0000 - 0x8001_7FFF)
        elif 0x80010000 <= addr < 0x80010000 + dram_size:
            rel = addr - 0x80010000
            end = min(rel + p_filesz, dram_size)
            dram[rel:end] = seg_data[:end-rel]

    return iram, dram

def write_mem(filename, byte_data):
    with open(filename, "w") as f:
        f.write("@00000000\n")
        # Find highest non-zero word to trim file length
        max_idx = len(byte_data)
        while max_idx > 4 and byte_data[max_idx-4:max_idx] == b'\x00\x00\x00\x00':
            max_idx -= 4
        # Guarantee at least 64 words written
        max_idx = max(max_idx, 256)

        for i in range(0, max_idx, 4):
            word = struct.unpack_from('<I', byte_data, i)[0]
            f.write(f"{word:08x}\n")

def main():
    if len(sys.argv) < 4:
        print("Usage: elf2mems.py <program.elf> <test_instr.mem> <test_data.mem>")
        sys.exit(1)

    elf_file = sys.argv[1]
    instr_file = sys.argv[2]
    data_file = sys.argv[3]

    iram, dram = parse_elf(elf_file)
    write_mem(instr_file, iram)
    write_mem(data_file, dram)
    print(f"[elf2mems] Converted {elf_file} -> {instr_file}, {data_file}")

if __name__ == "__main__":
    main()

