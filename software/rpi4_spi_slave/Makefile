#-----------------------------------------------------------------------------
# Raspberry Pi 4 bare-metal SPI-slave boot server for the 1TOPS SoC
#
#   make            -> build/kernel8.img           (needs an AArch64 bare-metal GCC)
#   make sdcard     -> build/sdcard/ = config.txt + kernel8.img (+ firmware if fetched)
#   make firmware   -> download start4.elf + fixup4.dat + bcm2711-rpi-4-b.dtb into build/sdcard/ (internet)
#   make dis        -> build/kernel8.dis           (disassembly, to review the hot loop)
#   make test       -> host unit tests (host gcc, no Pi needed)
#   make syntax     -> host gcc -fsyntax-only on the firmware C files
#
# Toolchain: CROSS=aarch64-none-elf- (Arm GNU Toolchain, bare metal; default)
#            or CROSS=aarch64-linux-gnu- (distribution cross compiler).
#-----------------------------------------------------------------------------

CROSS    ?= aarch64-none-elf-
CC       := $(CROSS)gcc
OBJCOPY  := $(CROSS)objcopy
OBJDUMP  := $(CROSS)objdump
HOSTCC   ?= gcc

BUILD    := build
SRC      := src
FW_URL   ?= https://raw.githubusercontent.com/raspberrypi/firmware/stable/boot

# -mgeneral-regs-only : no FP/SIMD registers (they may be trapped at EL2; not needed)
# -mstrict-align      : no unaligned accesses (data memory is Device memory, MMU off)
ARCHFLAGS := -mcpu=cortex-a72 -mgeneral-regs-only -mstrict-align
CFLAGS    := $(ARCHFLAGS) -O2 -std=c11 -ffreestanding -fno-stack-protector \
             -fno-pic -fno-pie -Wall -Wextra -I$(SRC)
ASFLAGS   := $(ARCHFLAGS)
LDFLAGS   := -nostdlib -nostartfiles -static -no-pie -T link.ld -Wl,--build-id=none

OBJS := $(BUILD)/boot.o $(BUILD)/main.o $(BUILD)/hw.o $(BUILD)/protocol.o $(BUILD)/libc_min.o

.PHONY: all sdcard firmware dis test syntax clean diag

all: $(BUILD)/kernel8.img

# UART diagnostic image (bench bring-up): build/diag/kernel8.img, see src/diag.c
diag: $(BUILD)/boot.o $(BUILD)/libc_min.o link.ld
	mkdir -p $(BUILD)/diag
	$(CC) $(CFLAGS) -c $(SRC)/diag.c -o $(BUILD)/diag/diag.o
	$(CC) $(CFLAGS) $(LDFLAGS) $(BUILD)/boot.o $(BUILD)/diag/diag.o $(BUILD)/libc_min.o -o $(BUILD)/diag/kernel8.elf -lgcc
	$(OBJCOPY) -O binary $(BUILD)/diag/kernel8.elf $(BUILD)/diag/kernel8.img
	@echo "built $(BUILD)/diag/kernel8.img ($$(wc -c < $(BUILD)/diag/kernel8.img) bytes): copy it over kernel8.img on the SD card"

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/%.o: $(SRC)/%.c $(wildcard $(SRC)/*.h) | $(BUILD)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD)/boot.o: $(SRC)/boot.S | $(BUILD)
	$(CC) $(ASFLAGS) -c $< -o $@

$(BUILD)/kernel8.elf: $(OBJS) link.ld
	$(CC) $(CFLAGS) $(LDFLAGS) $(OBJS) -o $@ -lgcc

$(BUILD)/kernel8.img: $(BUILD)/kernel8.elf
	$(OBJCOPY) -O binary $< $@
	@echo "built $@ ($$(wc -c < $@) bytes)"

dis: $(BUILD)/kernel8.elf
	$(OBJDUMP) -d $< > $(BUILD)/kernel8.dis
	@echo "disassembly: $(BUILD)/kernel8.dis (look for the GPLEV0 loop in main)"

sdcard: $(BUILD)/kernel8.img
	mkdir -p $(BUILD)/sdcard
	cp config.txt $(BUILD)/kernel8.img $(BUILD)/sdcard/
	@test -f $(BUILD)/sdcard/start4.elf -a -f $(BUILD)/sdcard/fixup4.dat || \
	  echo "NOTE: also put start4.elf and fixup4.dat in $(BUILD)/sdcard (make firmware, or copy them from any Raspberry Pi OS boot partition)"
	@echo "copy everything in $(BUILD)/sdcard/ to the FAT32 boot partition of the Pi's SD card"

firmware:
	mkdir -p $(BUILD)/sdcard
	curl -fL -o $(BUILD)/sdcard/start4.elf $(FW_URL)/start4.elf
	curl -fL -o $(BUILD)/sdcard/fixup4.dat $(FW_URL)/fixup4.dat
	curl -fL -o $(BUILD)/sdcard/bcm2711-rpi-4-b.dtb $(FW_URL)/bcm2711-rpi-4-b.dtb

test: | $(BUILD)
	$(HOSTCC) -std=c11 -O2 -Wall -Wextra -o $(BUILD)/test_slave_core test/test_slave_core.c
	$(HOSTCC) -std=c11 -O2 -Wall -Wextra -I$(SRC) -o $(BUILD)/test_protocol test/test_protocol.c $(SRC)/protocol.c
	./$(BUILD)/test_slave_core
	./$(BUILD)/test_protocol

syntax:
	$(HOSTCC) -std=c11 -fsyntax-only -ffreestanding -Wall -Wextra -I$(SRC) $(SRC)/main.c $(SRC)/hw.c $(SRC)/protocol.c $(SRC)/libc_min.c

clean:
	rm -rf $(BUILD)
