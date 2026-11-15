#!/bin/bash
# build_prog.sh <name>  ->  <name>.elf / .mem (one 32-bit little-endian word per line)
set -e
cd $(dirname $0)

PREFIX=""
if [ -n "$CV_SW_PREFIX" ] && command -v "${CV_SW_PREFIX}gcc" >/dev/null 2>&1; then
  PREFIX="$CV_SW_PREFIX"
elif command -v riscv-none-elf-gcc >/dev/null 2>&1; then
  PREFIX="riscv-none-elf-"
elif command -v riscv64-unknown-elf-gcc >/dev/null 2>&1; then
  PREFIX="riscv64-unknown-elf-"
elif command -v riscv32-unknown-elf-gcc >/dev/null 2>&1; then
  PREFIX="riscv32-unknown-elf-"
else
  echo "Error: No RISC-V GCC toolchain found in PATH" >&2
  exit 1
fi

${PREFIX}gcc -march=rv32i_zicsr -mabi=ilp32 -nostdlib -nostartfiles -Wl,-Ttext=0x80000000 -o $1.elf $1.S
${PREFIX}objcopy -O binary $1.elf $1.bin
python3 -c "
import struct,sys
b=open('$1.bin','rb').read(); b+=b'\0'*((-len(b))%4)
open('$1.mem','w').write(''.join('%08x\n'%struct.unpack('<I',b[i:i+4])[0] for i in range(0,len(b),4)))"
