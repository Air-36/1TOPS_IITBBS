#!/bin/bash
# Block-level debugger regression on Icarus Verilog
<<<<<<< HEAD:debugger_verification_tb/source/final_tests/08_debugger_verification/block/run_icarus.sh
# default RTL: <repo>/source (this suite lives in debugger_verification_tb/, outside source/)
R=${1:-$(cd $(dirname $0)/../../../../../source/debugger && pwd)}
=======
if ! command -v iverilog >/dev/null 2>&1; then
  export PATH=/tools/iverilog/bin:$PATH
fi
R=${1:-$(cd $(dirname $0)/../../../debugger && pwd)}
>>>>>>> origin/main:source/final_tests/08_debugger_verification/block/run_icarus.sh
cd $(dirname $0)
iverilog -g2012 -o sim_block -s tb_dbg_block -I$R \
  $R/socdebug_uart.v $R/socdebug_ft1248_control.v $R/socdebug_adp_control.v $R/socdebug_ahb.v \
  $R/riscv_debugger_top.sv $R/ahb_mux.sv $R/core_step_controller.sv $R/tb/f232h_ft1248_stream.v \
  tb_models.sv tb_dbg_block.sv || exit 1
vvp -n sim_block
