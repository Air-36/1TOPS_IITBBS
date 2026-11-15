#!/bin/bash
# run_sim.sh - real SoC SPI master RTL vs the Pi 4 software-slave timing model (iverilog)
set -e
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$HERE/../../../source/uncore"
OUT="$HERE/../build/sim"
mkdir -p "$OUT"
iverilog -g2012 -o "$OUT/tb.vvp" -s tb_spi_pi_slave \
  "$HERE/tb_spi_pi_slave.sv" "$SRC/spi_apb.sv" "$SRC/spi_controller.sv" "$SRC/spi_fifo.sv"
run() { echo "--- $*"; (cd "$OUT" && timeout 600 vvp -n tb.vvp "$@" | grep -v "^VCD" | grep "SCKDIV=\|RESULT\|byte\|TIMEOUT"); }
run +SCKDIV=99 +POLL=200  +LAT=300                 # 250 kHz, realistic Pi 4 loop
run +SCKDIV=99 +POLL=1000 +LAT=500                 # 250 kHz, a 5x slower Pi loop: still inside the budget
run +SCKDIV=24 +POLL=1000 +LAT=500 +EXPECT_FAIL    # today's 1 MHz with that slow loop: too fast
run +SCKDIV=99 +POLL=200  +LAT=300 +OLD_RXPOLL +EXPECT_FAIL  # the original RXDATA polling loop: loses bytes
