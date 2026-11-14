#!/bin/bash
# Full-SoC suite on Verilator.  run_verilator.sh <repo>/source [RAM_LATENCY]
# default RTL: <repo>/source (this suite lives in debugger_verification_tb/, outside source/)
R=${1:-$(cd $(dirname $0)/../../../../../source && pwd)}; LAT=${2:-0}
cd $(dirname $0)
export PATH=/usr/local/lib/python3.13/dist-packages/verilator/bin:$PATH
rm -rf src_lat && mkdir src_lat && cp $R/uncore/*.sv src_lat/ && sed -i "s/\.RAM_LATENCY(0)/.RAM_LATENCY($LAT)/" src_lat/uncore.sv
verilator --binary --timing -j 2 -Wno-fatal -Wno-lint -Wno-style -Wno-MULTIDRIVEN -Wno-INITIALDLY -Wno-ZERODLY -Wno-PINMISSING \
  -MAKEFLAGS "OPT_FAST=-O1 OPT_SLOW=-O0 OPT_GLOBAL=-O0" --top-module tb_soc_dbg_full -Mdir obj_soc_$LAT -o sim_soc_vl \
  -I$R/main -I$R/main/soc -I$R/components -Isrc_lat -I$R/debugger \
  $R/components/*.v $R/main/riscv_cpu.v $R/main/soc/multiplier_ahb.v $R/main/soc/riscv_soc_ahb.v src_lat/*.sv \
  $R/debugger/*.v $R/debugger/*.sv $R/debugger/tb/f232h_ft1248_stream.v tb_soc_dbg_full.sv > vl_build_$LAT.log 2>&1 || { grep -m 20 "%Error" vl_build_$LAT.log; exit 1; }
./obj_soc_$LAT/sim_soc_vl
