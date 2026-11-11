#!/bin/bash
# Full-SoC debugger regression on Icarus
if ! command -v iverilog >/dev/null 2>&1; then
  export PATH=/tools/iverilog/bin:$PATH
fi
R=${1:-$(cd $(dirname $0)/../../.. && pwd)}
cd $(dirname $0)
iverilog -g2012 -o sim_soc -s tb_soc_dbg_full -I$R/main -I$R/main/soc -I$R/components -I$R/uncore -I$R/debugger \
  $R/components/*.v $R/main/riscv_cpu.v $R/main/soc/multiplier_ahb.v $R/main/soc/riscv_soc_ahb.v $R/uncore/*.sv \
  $R/debugger/*.v $R/debugger/*.sv $R/debugger/tb/f232h_ft1248_stream.v tb_soc_dbg_full.sv || exit 1
stdbuf -o0 vvp -n sim_soc | grep -avE "^VCD|readmemh"
