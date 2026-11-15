#!/bin/bash
# Block-level debugger regression on Verilator 5 (timing + SVA)
# default RTL: <repo>/source (this suite lives in debugger_verification_tb/, outside source/)
R=${1:-$(cd $(dirname $0)/../../../../../source/debugger && pwd)}
cd $(dirname $0)
export PATH=/usr/local/lib/python3.13/dist-packages/verilator/bin:$PATH
rm -rf obj_block
verilator --binary --timing --assert -j 8 -MAKEFLAGS "OPT_FAST=-O1 OPT_SLOW=-O0 OPT_GLOBAL=-O0" -Wno-fatal -Wno-lint -Wno-style -Wno-MULTIDRIVEN -Wno-INITIALDLY -Wno-ZERODLY \
  --top-module tb_dbg_block -Mdir obj_block -o sim_block_vl -I$R \
  $R/socdebug_uart.v $R/socdebug_ft1248_control.v $R/socdebug_adp_control.v $R/socdebug_ahb.v \
  $R/riscv_debugger_top.sv $R/ahb_mux.sv $R/core_step_controller.sv $R/tb/f232h_ft1248_stream.v \
  tb_models.sv tb_dbg_block.sv sva_dbg.sv > vl_build.log 2>&1 || { tail -30 vl_build.log; exit 1; }
./obj_block/sim_block_vl
