#!/bin/bash
# run_sim.sh - iverilog check of the Basys 3 board top (board I/O driven by sim/tb_basys3_top.sv)
set -e
FPGA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$FPGA_DIR/../source"
OUT="$FPGA_DIR/sim/build"
mkdir -p "$OUT"
iverilog -g2012 -o "$OUT/tb_basys3_top.vvp" -s tb_basys3_top \
  -I "$SRC/components" -I "$SRC/debugger" -I "$SRC/main" -I "$SRC/main/soc" -I "$SRC/uncore" \
  "$FPGA_DIR/sim/tb_basys3_top.sv" \
  "$FPGA_DIR/top/tops_soc_fpga_top.sv" \
  "$SRC"/components/*.v "$SRC"/debugger/*.v "$SRC"/debugger/*.sv \
  "$SRC"/main/*.v "$SRC"/main/soc/*.v "$SRC"/uncore/*.sv
cd "$OUT" && vvp -n tb_basys3_top.vvp | grep -v "^VCD\|WARNING.*readmem"
