// =============================================================================
// tb_basys3_top.sv - RTL check of tops_soc_fpga_top (Digilent Basys 3 board top)
// The testbench plays the board and HTerm: it drives a 50 MHz clock on clk (the MMCM is
// bypassed in simulation), btnC, the slide switches and the USB-UART line, and checks the
// LEDs and PMOD pins (same checks as fpga/zcu102/sim/tb_zcu102_top.sv):
//   1. debugger banner + prompt after reset; SPI CS idle high
//   2. ADP write / read-back of DMEM; LED15 (UART RX activity)
//   3. ADP halt / resume -> LED0
//   4. btnC -> banner again
//   5. boot ROM drives SPI on PMOD JC after reset; with only the MISO pull-up it stops with
//      error 0xE1, read back through the debugger as on the bench (A 80017FFC / R)
//   6. SW0 dbg_sel -> LED1;  7. application UART on PMOD JA
// =============================================================================
`timescale 1ns/1ps
module tb_basys3_top;
  localparam integer CLK_FREQ = 50_000_000;
  localparam integer BAUD     = 115200;
  localparam integer BIT_CLKS = CLK_FREQ / BAUD;     // same integer divider as the debugger

  reg  clk = 1'b0;
  always #10 clk = ~clk;                             // 50 MHz (sim bypasses the MMCM)

  reg  btnc = 1'b1;                                  // btnC pressed at power-on
  reg  sw0 = 1'b0, sw1 = 1'b0;                       // dbg_sel, boot_mode
  reg  host_tx = 1'b1;                               // USB-UART: HTerm -> FPGA
  wire fpga_tx;
  reg  ja1 = 1'b1;                                   // app UART in (PMOD JA1)
  wire ja2;                                          // app UART out (PMOD JA2)
  reg  jc3 = 1'b1;                                   // SPI MISO: nothing attached, pull-up (XDC)
  wire jc1, jc2, jc4;                                // CS_n, MOSI, SCLK
  wire jb1, jb2, jb4;
  wire led0, led1, led15;
  pullup (jb4);

  tops_soc_fpga_top dut (
    .clk(clk), .reset_btn(btnc), .boot_mode(sw1),
    .dbg_sel(sw0), .uart_rx(host_tx), .uart_tx(fpga_tx),
    .ft1248_clk(jb1), .ft1248_ss_n(jb2), .ft1248_miso(1'b1), .ft1248_miosio(jb4),
    .UARTSin(ja1), .UARTSout(ja2),
    .spi_cs_n(jc1), .spi_mosi(jc2), .spi_miso(jc3), .spi_sclk(jc4),
    .led_core_halted(led0), .led_dbg_sel(led1), .led_rx_detect(led15));

  // ---------------- HTerm model: receive ----------------
  reg [8*512-1:0] rxbuf;
  integer         rxlen = 0;
  task automatic clear_rx; begin rxbuf = 0; rxlen = 0; end endtask
  always begin : uart_rx_monitor
    integer i; reg [7:0] c;
    @(negedge fpga_tx);
    repeat (BIT_CLKS / 2) @(posedge clk);
    if (fpga_tx == 1'b0) begin
      for (i = 0; i < 8; i = i + 1) begin repeat (BIT_CLKS) @(posedge clk); c[i] = fpga_tx; end
      repeat (BIT_CLKS) @(posedge clk);
      rxbuf = {rxbuf[8*511-1:0], c};
      rxlen = rxlen + 1;
    end
  end
  function automatic [7:0] rxchar(input integer back);
    rxchar = rxbuf[8*back +: 8];
  endfunction

  // ---------------- HTerm model: type ----------------
  task automatic uart_send_byte(input [7:0] b);
    integer i;
    begin
      host_tx = 1'b0; repeat (BIT_CLKS) @(posedge clk);
      for (i = 0; i < 8; i = i + 1) begin host_tx = b[i]; repeat (BIT_CLKS) @(posedge clk); end
      host_tx = 1'b1; repeat (BIT_CLKS) @(posedge clk);
    end
  endtask
  task automatic adp_send(input [8*32-1:0] s, input integer n);
    integer i;
    begin
      for (i = n - 1; i >= 0; i = i - 1) uart_send_byte(s[8*i +: 8]);
      uart_send_byte(8'h0d);
    end
  endtask
  task automatic wait_prompt(input integer max_cycles, output bit seen);
    integer t;
    begin
      seen = 0;
      for (t = 0; t < max_cycles && !seen; t = t + 1) begin
        @(posedge clk);
        if (rxlen > 0 && rxchar(0) == "]") seen = 1;
      end
    end
  endtask
  function automatic bit rx_has(input [8*16-1:0] s, input integer n);
    integer i, j; bit m;
    begin
      rx_has = 0;
      for (i = 0; i + n <= rxlen && i < 512 && !rx_has; i = i + 1) begin
        m = 1;
        for (j = 0; j < n; j = j + 1)
          if (rxbuf[8*(i + n - 1 - j) +: 8] != s[8*(n - 1 - j) +: 8]) m = 0;
        if (m) rx_has = 1;
      end
    end
  endfunction
  task automatic show_rx;
    integer i; reg [7:0] c;
    begin
      $write("      rx: \"");
      for (i = (rxlen < 80 ? rxlen : 80) - 1; i >= 0; i = i - 1) begin
        c = rxchar(i);
        if (c == 8'h0d) $write("\\r"); else if (c == 8'h0a) $write("\\n"); else $write("%c", c);
      end
      $display("\"");
    end
  endtask

  integer fails = 0;
  task automatic check(input bit cond, input [8*72-1:0] what);
    begin
      if (cond) $display("  [PASS] %0s", what);
      else begin $display("  [FAIL] %0s", what); fails = fails + 1; end
    end
  endtask
  task automatic press_btnc;
    begin btnc = 1'b1; repeat (50) @(posedge clk); btnc = 1'b0; end
  endtask

  // ---------------- SPI pin activity (PMOD JC) ----------------
  integer cs_low_cycles = 0, sclk_edges = 0;
  reg     sclk_q = 1'b1;
  always @(posedge clk) begin
    if (jc1 == 1'b0) cs_low_cycles <= cs_low_cycles + 1;
    sclk_q <= jc4;
    if (sclk_q != jc4) sclk_edges <= sclk_edges + 1;
  end

  bit seen;
  initial begin
    $display("=== tb_basys3_top: 1TOPS SoC on Basys 3 (board I/O, HTerm on the USB-UART) ===");
    clear_rx();

    // 1. Power-on: btnC released -> banner. The boot ROM tries SPI meanwhile (nothing attached).
    repeat (20) @(posedge clk); btnc = 1'b0;
    wait_prompt(400_000, seen);
    show_rx();
    check(seen && rx_has("0x50c1ab04", 10), "1. debugger banner 0x50c1ab04 + prompt on the USB-UART (A18)");
    check(jc1 === 1'b1, "   SPI CS_n (JC1) idle high after the boot ROM gave up");

    // 2. ADP write + read-back of DMEM
    clear_rx(); adp_send("A 80010000", 10); wait_prompt(200_000, seen);
    check(led15 === 1'b1, "2. LED15 UART RX activity after typing");
    clear_rx(); adp_send("W 1234abcd", 10); wait_prompt(200_000, seen);
    clear_rx(); adp_send("A 80010000", 10); wait_prompt(200_000, seen);
    clear_rx(); adp_send("R", 1);           wait_prompt(200_000, seen);
    show_rx();
    check(seen && rx_has("R 0x1234abcd", 12), "   ADP W/R of DMEM 0x8001_0000");
    check(dut.soc.uncore.ram_d.mem[0] === 32'h1234abcd, "   DMEM word 0 really written (backdoor check)");

    // 3. Halt / resume -> LED0
    clear_rx(); adp_send("C 0202", 6); wait_prompt(200_000, seen);
    check(led0 === 1'b1, "3. C 0202 halts the core -> LED0 on");
    clear_rx(); adp_send("C 0102", 6); wait_prompt(200_000, seen);
    check(led0 === 1'b0, "   C 0102 resumes the core -> LED0 off");

    // 4. btnC -> banner again; 5. the boot ROM drives SPI and stops with E1 (MISO pull-up only)
    cs_low_cycles = 0; sclk_edges = 0;
    clear_rx(); press_btnc();
    wait_prompt(400_000, seen);
    check(seen && rx_has("0x50c1ab04", 10), "4. btnC -> banner again");
    check(cs_low_cycles > 0 && sclk_edges > 16, "5. boot ROM drives SPI CS_n/SCLK on PMOD JC1/JC4");
    $display("      CS low for %0d cycles, %0d SCLK edges", cs_low_cycles, sclk_edges);
    check(jc1 === 1'b1, "   CS_n released after the bad magic");
    clear_rx(); adp_send("A 80017FFC", 10); wait_prompt(200_000, seen);
    clear_rx(); adp_send("R", 1);           wait_prompt(200_000, seen);
    show_rx();
    check(seen && rx_has("R 0x000000e1", 12), "   debugger reads error 0xE1 at 0x8001_7FFC (no partner)");

    // 6. dbg_sel (SW0) -> LED1
    sw0 = 1'b1; repeat (5) @(posedge clk);
    check(led1 === 1'b1 && dut.soc.dbg_sel === 1'b1, "6. SW0 dbg_sel -> LED1 on, SoC dbg_sel = 1");
    sw0 = 1'b0;

    // 7. Application UART on PMOD JA
    ja1 = 1'b0; #1;
    check(dut.soc.UARTSin === 1'b0, "7. PMOD JA1 reaches the SoC UARTSin");
    ja1 = 1'b1; #1;
    check(dut.soc.UARTSin === 1'b1 && ja2 === dut.soc.UARTSout, "   UARTSout drives PMOD JA2");

    $display("=== RESULT: %0s (%0d failures) ===", fails ? "FAILED" : "ALL PASS", fails);
    $finish;
  end
  initial begin #60_000_000; $display("=== RESULT: FAILED (timeout) ==="); $finish; end
endmodule
