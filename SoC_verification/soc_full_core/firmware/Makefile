# ==============================================================================
# Makefile: Firmware compilation for 1TOPS RISC-V SoC Verification
# ==============================================================================

TOOLCHAIN_BIN := /home/23EC01043/tools/xpack-riscv-none-elf-gcc-15.2.0-1/bin
CC            := $(TOOLCHAIN_BIN)/riscv-none-elf-gcc
OBJCOPY       := $(TOOLCHAIN_BIN)/riscv-none-elf-objcopy
OBJDUMP       := $(TOOLCHAIN_BIN)/riscv-none-elf-objdump
PYTHON        := python3

BSP_DIR       := ../bsp
LDSCRIPT      := $(BSP_DIR)/link.ld
CRT0          := $(BSP_DIR)/crt0.s
ELF2MEMS      := $(BSP_DIR)/elf2mems.py

CFLAGS        := -march=rv32i_zicsr -mabi=ilp32 -O1 -nostdlib -nostartfiles \
                 -T $(LDSCRIPT) -I$(BSP_DIR) -Wall

SRCS          := $(wildcard *.c)
TESTS         := $(basename $(SRCS))
ELFS          := $(addsuffix .elf, $(TESTS))
DIS           := $(addsuffix .dis, $(TESTS))
MEMS          := $(addsuffix _instr.mem, $(TESTS))

.PHONY: all clean

all: $(ELFS) $(DIS) $(MEMS)

%.elf: %.c $(CRT0) $(LDSCRIPT) $(BSP_DIR)/soc_regs.h
	$(CC) $(CFLAGS) $(CRT0) $< -o $@

%.dis: %.elf
	$(OBJDUMP) -d -S $< > $@

%_instr.mem %_data.mem: %.elf $(ELF2MEMS)
	$(PYTHON) $(ELF2MEMS) $< $*_instr.mem $*_data.mem

clean:
	rm -f *.elf *.dis *.mem

