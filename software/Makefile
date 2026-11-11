RISCV_BIN = /opt/riscv/bin
ifneq ($(wildcard $(RISCV_BIN)/riscv64-unknown-elf-gcc),)
  RISCV_PREFIX ?= $(RISCV_BIN)/riscv64-unknown-elf-
else
  RISCV_PREFIX ?= riscv64-unknown-elf-
endif

CC = $(RISCV_PREFIX)gcc
OBJCOPY = $(RISCV_PREFIX)objcopy

# Boot ROMs (internal: 0x1000, external: 0x80007C00). loader.S is #included, so -Icommon.
CROSS ?= $(RISCV_PREFIX)
ARCH  ?= -march=rv32i -mabi=ilp32
CFLAGS2 = $(ARCH) -nostdlib -nostartfiles -Icommon
# The internal ROM is RTL: a generated case table in source/uncore/rom_ahb.sv (see `make rom`)
ROM_RTL = ../source/uncore/rom_ahb.sv
ROM_MEM = ../source/uncore/bootrom.mem

CFLAGS = -march=rv32i -mabi=ilp32 -mcmodel=medany -nostartfiles -nostdlib -T link.ld -O2

all: test_instr.mem test_data.mem factorial.bin trap_test.bin profile_accel.bin spi_test.bin step_test.bin build/bootrom_int.elf build/bootrom_ext.elf

test.elf: crt0.S main.c
	$(CC) $(CFLAGS) $^ -o $@

test_instr.mem test_data.mem: test.elf
	$(OBJCOPY) -O binary $< test.bin
	python3 elf2mem.py test.bin test_instr.mem test_data.mem

factorial.elf: factorial.S
	$(CC) -march=rv32i -mabi=ilp32 -nostartfiles -nostdlib -T link.ld $< -o $@

factorial.bin: factorial.elf
	$(OBJCOPY) -O binary --only-section=.text $< $@
	mkdir -p ../fpga
	cp -f $@ ../fpga/factorial.bin

step_test.elf: step_test.S
	$(CC) -march=rv32i -mabi=ilp32 -nostartfiles -nostdlib -T link.ld $< -o $@

step_test.bin: step_test.elf
	$(OBJCOPY) -O binary --only-section=.text $< $@
	mkdir -p ../fpga
	cp -f $@ ../fpga/step_test.bin

trap_test.elf: trap_test.S
	$(CC) -march=rv32i_zicsr -mabi=ilp32 -nostartfiles -nostdlib -T link.ld $< -o $@

trap_test.bin: trap_test.elf
	$(OBJCOPY) -O binary --only-section=.text $< $@
	mkdir -p ../fpga
	cp -f $@ ../fpga/trap_test.bin

profile_accel.elf: profile_accel.S
	$(CC) -march=rv32i -mabi=ilp32 -nostartfiles -nostdlib -T link.ld $< -o $@

profile_accel.bin: profile_accel.elf
	$(OBJCOPY) -O binary --only-section=.text $< $@
	mkdir -p ../fpga
	cp -f $@ ../fpga/profile_accel.bin

spi_test.elf: spi_test.S
	$(CC) -march=rv32i -mabi=ilp32 -nostartfiles -nostdlib -T link.ld $< -o $@

spi_test.bin: spi_test.elf
	$(OBJCOPY) -O binary --only-section=.text $< $@
	mkdir -p ../fpga
	cp -f $@ ../fpga/spi_test.bin

build:
	mkdir -p build

build/bootrom_int.elf: bootrom_int/bootrom_int.S bootrom_int/bootrom_int.ld common/loader.S | build
	$(CROSS)gcc $(CFLAGS2) -T bootrom_int/bootrom_int.ld $< -o $@
	$(CROSS)size $@

# Write the internal boot ROM into the RTL: rewrites the generated case table in rom_ahb.sv
# and bootrom.mem. Explicit target (not part of `all`) because it edits RTL source.
rom: build/bootrom_int.elf
	python3 gen_bootrom.py --elf $< --rom $(ROM_RTL) --mem $(ROM_MEM) --objdump $(CROSS)objdump

build/bootrom_ext.elf: bootrom_ext/bootrom_ext.S bootrom_ext/bootrom_ext.ld common/loader.S | build
	$(CROSS)gcc $(CFLAGS2) -T bootrom_ext/bootrom_ext.ld $< -o $@
	$(CROSS)size $@

# usage: make image MODE=0|1 TEST=path/to/test.elf   ->  build/flash.bin (SPI boot stream)
ifneq ($(filter image,$(MAKECMDGOALS)),)
  ifeq ($(and $(MODE),$(TEST)),)
    $(error usage: make image MODE=0|1 TEST=path/to/test.elf)
  endif
endif
image: build/bootrom_ext.elf $(TEST)
	python3 make_image.py --mode $(MODE) --test $(TEST) --ext build/bootrom_ext.elf -o build/flash.bin --dump

.PHONY: all clean image rom

clean:
	rm -f test.elf test.bin test_instr.mem test_data.mem factorial.elf factorial.bin step_test.elf step_test.bin trap_test.elf trap_test.bin profile_accel.elf profile_accel.bin spi_test.elf spi_test.bin ../fpga/factorial.bin ../fpga/step_test.bin ../fpga/trap_test.bin ../fpga/profile_accel.bin ../fpga/spi_test.bin
	rm -rf build
