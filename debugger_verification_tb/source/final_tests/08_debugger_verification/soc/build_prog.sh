#!/bin/bash
# build_prog.sh <name>  ->  <name>.elf / .mem (one 32-bit little-endian word per line)
set -e
cd $(dirname $0)
riscv64-unknown-elf-gcc -march=rv32i_zicsr -mabi=ilp32 -nostdlib -nostartfiles -Wl,-Ttext=0x80000000 -o $1.elf $1.S
riscv64-unknown-elf-objcopy -O binary $1.elf $1.bin
python3 -c "
import struct,sys
b=open('$1.bin','rb').read(); b+=b'\0'*((-len(b))%4)
open('$1.mem','w').write(''.join('%08x\n'%struct.unpack('<I',b[i:i+4])[0] for i in range(0,len(b),4)))"
