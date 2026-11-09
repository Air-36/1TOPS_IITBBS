#!/bin/bash
# Block-level debugger regression on Icarus Verilog
R=${1:-$(cd $(dirname $0)/../../../debugger && pwd)}
cd $(dirname $0)
iverilog -g2012 -o sim_block -s tb_dbg_block -I$R \
  $R/socdebug_uart.v $R/socdebug_ft1248_control.v $R/socdebug_adp_control.v $R/socdebug_ahb.v \
  $R/riscv_debugger_top.sv $R/ahb_mux.sv $R/core_step_controller.sv $R/tb/f232h_ft1248_stream.v \
  tb_models.sv tb_dbg_block.sv || exit 1
vvp -n sim_block
