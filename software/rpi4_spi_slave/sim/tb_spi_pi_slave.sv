// =============================================================================
// tb_spi_pi_slave.sv - the REAL SoC SPI master RTL (source/uncore/spi_apb.sv,
// spi_controller.sv, spi_fifo.sv) against a timed model of the Pi 4 software
// slave (same algorithm as src/slave_core.h).
//
// The APB sequence is the boot loader's (software/common/loader.S):
//   spi_init: SCKDIV, SCKMODE=3, CSID=0, CSDEF=0xF, CSMODE=AUTO, FMT=8-bit MSB-first,
//             drain RX
//   image   : CSMODE=HOLD; per byte: wait TX not full, write 0 to TXDATA, poll RXDATA
//             until not empty; CSMODE=AUTO at the end
// Two images back to back (mode 1: internal ROM loads the ext ROM image, the ext ROM
// re-runs spi_init and loads the test image), with the FPGA top's registered CS.
//
// Pi model: polls (CS, SCLK) every PI_POLL_NS (+/- jitter); MISO changes PI_LAT_NS
// after the poll that saw the falling edge.
// Plusargs: +SCKDIV=<n> +POLL=<ns> +LAT=<ns> +EXPECT_FAIL +OLD_RXPOLL
// =============================================================================
`timescale 1ns/1ps
module tb_spi_pi_slave;
  // ---------------------------------------------------------------- clock/reset
  reg PCLK = 0, PRESETn = 0;
  always #10 PCLK = ~PCLK;                       // 50 MHz SoC clock

  // ---------------------------------------------------------------- APB / DUT
  reg         PSEL = 0, PENABLE = 0, PWRITE = 0;
  reg  [7:0]  PADDR = 0;
  reg  [31:0] PWDATA = 0;
  wire [31:0] PRDATA;
  wire        PREADY, SPIOut, SPIIntr, SPICLK;
  wire [3:0]  SPICS;
  reg         miso = 1'b1;

  spi_apb #(.XLEN(32), .SPI_LOOPBACK_TEST(0)) dut (
    .PCLK(PCLK), .PRESETn(PRESETn), .PSEL(PSEL), .PADDR(PADDR), .PWDATA(PWDATA),
    .PWRITE(PWRITE), .PENABLE(PENABLE), .PREADY(PREADY), .PRDATA(PRDATA),
    .SPIOut(SPIOut), .SPIIn(miso), .SPICS(SPICS), .SPIIntr(SPIIntr), .SPICLK(SPICLK));

  // FPGA top: CS re-registered on the SoC clock (tops_soc_*_top.sv)
  reg pin_cs = 1'b1;
  always @(posedge PCLK) pin_cs <= PRESETn ? SPICS[0] : 1'b1;
  wire pin_sclk = SPICLK;

  task automatic apb_write(input [7:0] a, input [31:0] d);
    begin
      @(posedge PCLK); PSEL <= 1; PENABLE <= 0; PWRITE <= 1; PADDR <= a; PWDATA <= d;
      @(posedge PCLK); PENABLE <= 1;
      @(posedge PCLK); PSEL <= 0; PENABLE <= 0; PWRITE <= 0;
    end
  endtask
  task automatic apb_read(input [7:0] a, output [31:0] d);
    begin
      @(posedge PCLK); PSEL <= 1; PENABLE <= 0; PWRITE <= 0; PADDR <= a;
      @(posedge PCLK); PENABLE <= 1;
      @(posedge PCLK); d = PRDATA; PSEL <= 0; PENABLE <= 0;
    end
  endtask

  localparam SCKDIV_R = 8'h00, SCKMODE_R = 8'h04, CSID_R = 8'h10, CSDEF_R = 8'h14,
             CSMODE_R = 8'h18, FMT_R = 8'h40, TXDATA_R = 8'h48, RXDATA_R = 8'h4C,
             RXMARK_R = 8'h54, IP_R = 8'h74;

  integer sckdiv = 99;
  task automatic spi_init;                       // loader.S spi_init
    reg [31:0] d;
    begin
      apb_write(SCKDIV_R, sckdiv);
      apb_write(SCKMODE_R, 3);
      apb_write(CSID_R, 0);
      apb_write(CSDEF_R, 4'hF);
      apb_write(CSMODE_R, 0);
      apb_write(FMT_R, 32'h0008_0000);
      apb_write(RXMARK_R, 0);                  // RX watermark: pending when >= 1 byte
      d = 0;
      while (d[31] == 1'b0) apb_read(RXDATA_R, d);   // drain stale RX bytes
    end
  endtask

  // loader.S spi_read_byte (+ CPU overhead). Two variants:
  //   +OLD_RXPOLL : the original loop "poll RXDATA until not empty". Each RXDATA read can
  //                 pop the FIFO, and a byte arriving between the read's setup and access
  //                 edges is popped while the read reports "empty" -> the byte is LOST.
  //   default     : the fixed loop: poll SPI_IP bit 1 (RX watermark = FIFO not empty,
  //                 RXMARK = 0; reading IP has no side effect), then read RXDATA once.
  integer old_rxpoll = 0;
  task automatic spi_read_byte(output [7:0] b);
    reg [31:0] d;
    begin
      d = 32'h8000_0000;
      while (d[31]) apb_read(TXDATA_R, d);       // wait while TX FIFO full
      apb_write(TXDATA_R, 0);                    // dummy byte -> 8 clocks
      if (old_rxpoll) begin
        d = 32'h8000_0000;
        while (d[31]) apb_read(RXDATA_R, d);     // racy: may pop a byte while reporting empty
      end else begin
        d = 0;
        while (d[1] == 1'b0) apb_read(IP_R, d);  // wait for "RX FIFO not empty"
        d = 32'h8000_0000;
        while (d[31]) apb_read(RXDATA_R, d);     // single read (loop only as a safety net)
      end
      b = d[7:0];
      repeat (6 + ($urandom % 10)) @(posedge PCLK); // store + loop overhead in the loader
    end
  endtask

  // ---------------------------------------------------------------- Pi model
  reg [7:0] stream [0:4095];
  integer   s_len = 0, s_ptr = 0, s_bit = 0, s_cur = 8'hFF, s_prev = 1;
  integer   poll_ns = 200, lat_ns = 300;

  task automatic slv_finish; begin
    if (s_ptr < s_len) s_ptr = s_ptr + 1;
    s_bit = 0;
    s_cur = (s_ptr < s_len) ? stream[s_ptr] : 8'hFF;
  end endtask

  initial begin : pi_poll
    integer cs, sclk, v, step;
    #50;
    forever begin
      step = poll_ns + (($urandom % (poll_ns / 2 + 1)) - poll_ns / 4);   // +/- 25 % jitter
      #(step);
      cs = pin_cs; sclk = pin_sclk;
      if (cs) begin                                  // idle: R2/R3
        if (s_bit == 8) slv_finish; else s_bit = 0;
        s_prev = sclk;
      end else if (s_prev && !sclk) begin            // falling edge: drive next bit
        if (s_bit == 8) slv_finish;
        v = (s_cur >> (7 - s_bit)) & 1;
        s_bit = s_bit + 1;
        miso <= #(lat_ns) v[0];
        s_prev = sclk;
      end else begin
        if (s_bit == 8) slv_finish;                  // advance off the edge path
        s_prev = sclk;
      end
    end
  end

  // ---------------------------------------------------------------- SCLK measurement
  realtime t_fall_prev = 0, min_period = 1e9;
  always @(negedge pin_sclk) begin
    if (t_fall_prev > 0 && ($realtime - t_fall_prev) < min_period) min_period = $realtime - t_fall_prev;
    t_fall_prev = $realtime;
  end

  // ---------------------------------------------------------------- test
  integer i, n1, n2, errors, expect_fail;
  reg [7:0] b;
  initial begin
    if (!$value$plusargs("SCKDIV=%d", sckdiv)) sckdiv = 99;
    if (!$value$plusargs("POLL=%d", poll_ns))  poll_ns = 200;
    if (!$value$plusargs("LAT=%d", lat_ns))    lat_ns = 300;
    expect_fail = $test$plusargs("EXPECT_FAIL");
    old_rxpoll  = $test$plusargs("OLD_RXPOLL");
    n1 = 64; n2 = 192; errors = 0;
    s_len = n1 + n2;
    for (i = 0; i < s_len; i = i + 1) stream[i] = $urandom;
    stream[0] = "B"; stream[1] = "O"; stream[2] = "O"; stream[3] = "T";   // magic, as in a real stream
    s_ptr = 0; s_bit = 0; s_cur = stream[0]; s_prev = 1;                   // armed (R4)

    repeat (5) @(posedge PCLK); PRESETn = 1;

    // image 1 (internal ROM loading the ext ROM image)
    spi_init;
    apb_write(CSMODE_R, 2);
    for (i = 0; i < n1; i = i + 1) begin
      spi_read_byte(b);
      if (b !== stream[i]) begin errors = errors + 1; if (errors < 5) $display("  image1 byte %0d: got %02x exp %02x", i, b, stream[i]); end
    end
    apb_write(CSMODE_R, 0);
    repeat (500) @(posedge PCLK);                    // jump to the ext ROM

    // image 2 (ext ROM: spi_init again, then the test image; the stream continues, R1)
    spi_init;
    apb_write(CSMODE_R, 2);
    for (i = 0; i < n2; i = i + 1) begin
      spi_read_byte(b);
      if (b !== stream[n1 + i]) begin errors = errors + 1; if (errors < 5) $display("  image2 byte %0d: got %02x exp %02x", i, b, stream[n1 + i]); end
    end
    apb_write(CSMODE_R, 0);
    repeat (200) @(posedge PCLK);

    $display("SCKDIV=%0d  SCLK=%0.1f kHz  Pi poll=%0d ns (+/-25%%)  write latency=%0d ns  -> %0d bytes, %0d errors, pointer=%0d/%0d, CS idle=%0d",
             sckdiv, 1e6 / min_period, poll_ns, lat_ns, n1 + n2, errors, s_ptr, s_len, pin_cs);
    if (expect_fail)
      $display("RESULT: %s (failure expected: too slow for this SCLK)", errors ? "FAILS AS EXPECTED" : "UNEXPECTED PASS");
    else
      $display("RESULT: %s", (errors == 0 && s_ptr == s_len && pin_cs == 1) ? "PASS" : "FAIL");
    $finish;
  end
  initial begin
    #40_000_000;
    $display("TIMEOUT: the loader is still waiting for a byte (one was lost)");
    $display("RESULT: %s", expect_fail ? "FAILS AS EXPECTED (hang)" : "FAIL");
    $finish;
  end
endmodule
