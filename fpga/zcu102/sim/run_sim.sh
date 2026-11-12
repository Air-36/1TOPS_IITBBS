#!/bin/bash
# run_sim.sh - iverilog check of the ZCU102 top (board I/O driven by sim/tb_zcu102_top.sv)
set -e
ZCU_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ZCU_DIR/../../source"
OUT="$ZCU_DIR/sim/build"
mkdir -p "$OUT"
iverilog -g2012 -o "$OUT/tb_zcu102_top.vvp" -s tb_zcu102_top \
  -I "$SRC/components" -I "$SRC/debugger" -I "$SRC/main" -I "$SRC/main/soc" -I "$SRC/uncore" \
  "$ZCU_DIR/sim/tb_zcu102_top.sv" \
  "$ZCU_DIR/top/tops_soc_zcu102_top.sv" \
  "$SRC"/components/*.v "$SRC"/debugger/*.v "$SRC"/debugger/*.sv \
  "$SRC"/main/*.v "$SRC"/main/soc/*.v "$SRC"/uncore/*.sv
cd "$OUT" && vvp -n tb_zcu102_top.vvp | grep -v "^VCD\|WARNING.*readmem"
