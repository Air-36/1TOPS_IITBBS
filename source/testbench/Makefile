VLIB ?= vlib
VLOG ?= vlog
VSIM ?= vsim
VERILATOR ?= verilator
VFLAGS = -Wall -Wno-fatal --trace -cc --exe -f ../../filelist.f --top-module tb
INC_DIRS = -I../../src/soc_top -I../../src/uncore -I../../src/generic/mem -I../../src/accelerator -I../../config

all: questa

questa:
	cd ../.. && $(VLIB) work && $(VLOG) -sv -f filelist.f +incdir+source/main/soc +incdir+source/uncore +incdir+source/components +incdir+source/debugger $(CURDIR)/tb.sv && $(VSIM) -c -do "run -all; quit" work.tb

sim:
	cd ../.. && $(VERILATOR) -Wall -Wno-fatal -Wno-TIMESCALEMOD --timescale 1ns/1ps --trace -cc --exe -f filelist.f --top-module tb -Isource/main/soc -Isource/uncore -Isource/components -Isource/debugger -Mdir source/testbench/obj_dir $(CURDIR)/sim_main.cpp $(CURDIR)/tb.sv
	make -j -C obj_dir -f Vtb.mk Vtb

run: questa

clean:
	rm -rf obj_dir work transcript *.wlf trace.vcd test_instr.mem test_data.mem sim_out.txt
