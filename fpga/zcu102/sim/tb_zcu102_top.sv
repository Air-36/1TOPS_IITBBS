// =============================================================================
// tb_zcu102_top.sv - RTL check of tops_soc_zcu102_top (ZCU102 board top, PL-only)
// The testbench plays the board and HTerm: it drives a 50 MHz clock on CLK_125_P (the
// MMCM is bypassed in simulation, as on Basys 3), the CPU_RESET button, the DIP switches,
// and the CP2108 UART line, and checks the LEDs and PMOD pins:
//   1. debugger banner + prompt on the USB-UART after reset
//   2. ADP write / read-back of DMEM; LED2 (UART RX activity)
//   3. ADP halt / resume -> LED0 (core halted)
//   4. CPU_RESET button -> banner again
//   5. DIP SW13.2 boot_mode -> LED3, SYSCTRL strap; boot ROM mode 1 drives SPI on PMOD0,
//      LED6 (SPI activity)
//   6. DIP SW13.1 dbg_sel -> LED1
//   7. application UART on PMOD1, heartbeat and clock LEDs
// =============================================================================
`timescale 1ns/1ps
module tb_zcu102_top;
  localparam integer CLK_FREQ = 50_000_000;
  localparam integer BAUD     = 115200;
  localparam integer BIT_CLKS = CLK_FREQ / BAUD;     // same integer divider as the debugger

  reg  clk = 1'b0;
  always #10 clk = ~clk;                             // 50 MHz (sim bypasses the MMCM)

  reg  cpu_reset = 1'b1;                             // SW20 pressed at power-on
  reg  dip0 = 1'b0, dip1 = 1'b0;                     // SW13.1 dbg_sel, SW13.2 boot_mode
  reg  host_tx = 1'b1;                               // CP2108 TX -> FPGA RX (HTerm typing)
  wire fpga_tx;                                      // FPGA TX -> CP2108 RX (HTerm display)
  reg  pmod0_2 = 1'b1, pmod0_6 = 1'b1, pmod1_0 = 1'b1;
  wire pmod0_0, pmod0_1, pmod0_3, pmod0_4, pmod0_5, pmod0_7, pmod1_1;
  wire [7:0] led;
  pullup (pmod0_7);

  tops_soc_zcu102_top dut (
    .CLK_125_P(clk), .CLK_125_N(~clk),
    .CPU_RESET(cpu_reset), .GPIO_DIP_SW0(dip0), .GPIO_DIP_SW1(dip1),
    .UART2_TXD_O_FPGA_RXD(host_tx), .UART2_RXD_I_FPGA_TXD(fpga_tx),
    .PMOD0_0(pmod0_0), .PMOD0_1(pmod0_1), .PMOD0_2(pmod0_2), .PMOD0_3(pmod0_3),
    .PMOD0_4(pmod0_4), .PMOD0_5(pmod0_5), .PMOD0_6(pmod0_6), .PMOD0_7(pmod0_7),
    .PMOD1_0(pmod1_0), .PMOD1_1(pmod1_1),
    .GPIO_LED_0(led[0]), .GPIO_LED_1(led[1]), .GPIO_LED_2(led[2]), .GPIO_LED_3(led[3]),
    .GPIO_LED_4(led[4]), .GPIO_LED_5(led[5]), .GPIO_LED_6(led[6]), .GPIO_LED_7(led[7]));

  // ---------------- HTerm model: receive what the FPGA sends ----------------
  reg [8*512-1:0] rxbuf;
  integer         rxlen = 0;
  task automatic clear_rx; begin rxbuf = 0; rxlen = 0; end endtask

  always begin : uart_rx_monitor
    integer i; reg [7:0] c;
    @(negedge fpga_tx);
    repeat (BIT_CLKS / 2) @(posedge clk);
    if (fpga_tx == 1'b0) begin
      for (i = 0; i < 8; i = i + 1) begin
        repeat (BIT_CLKS) @(posedge clk);
        c[i] = fpga_tx;
      end
      repeat (BIT_CLKS) @(posedge clk);
      rxbuf = {rxbuf[8*511-1:0], c};
      rxlen = rxlen + 1;
    end
  end

  function automatic [7:0] rxchar(input integer back);
    rxchar = rxbuf[8*back +: 8];
  endfunction

  // ---------------- HTerm model: type characters ----------------
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
  task automatic check(input bit cond, input [8*64-1:0] what);
    begin
      if (cond) $display("  [PASS] %0s", what);
      else begin $display("  [FAIL] %0s", what); fails = fails + 1; end
    end
  endtask

  task automatic press_cpu_reset;
    begin cpu_reset = 1'b1; repeat (50) @(posedge clk); cpu_reset = 1'b0; end
  endtask

  // ---------------- SPI pin activity (PMOD0) ----------------
  integer cs_low_cycles = 0, sclk_edges = 0;
  reg     sclk_q = 1'b1;
  always @(posedge clk) begin
    if (pmod0_0 == 1'b0) cs_low_cycles <= cs_low_cycles + 1;
    sclk_q <= pmod0_3;
    if (sclk_q != pmod0_3) sclk_edges <= sclk_edges + 1;
  end

  bit seen;
  reg [24:0] hb0;
  initial begin
    $display("=== tb_zcu102_top: 1TOPS SoC on ZCU102 (board I/O, HTerm on the CP2108 UART) ===");
    clear_rx();

    // 1. Power-on: CPU_RESET released -> banner
    repeat (20) @(posedge clk); cpu_reset = 1'b0;
    wait_prompt(400_000, seen);
    show_rx();
    check(seen && rx_has("0x50c1ab04", 10), "1. debugger banner 0x50c1ab04 + prompt on the USB-UART (F13)");
    check(pmod0_0 === 1'b1, "   SPI CS_n (PMOD0_0) idle high");
    check(led[4] === 1'b1,  "   LED4 clock locked");

    // 2. ADP write + read-back of DMEM, typed on the USB-UART (E13)
    clear_rx(); adp_send("A 80010000", 10); wait_prompt(200_000, seen);
    check(led[2] === 1'b1, "2. LED2 UART RX activity after typing");
    clear_rx(); adp_send("W 1234abcd", 10); wait_prompt(200_000, seen);
    clear_rx(); adp_send("A 80010000", 10); wait_prompt(200_000, seen);
    clear_rx(); adp_send("R", 1);           wait_prompt(200_000, seen);
    show_rx();
    check(seen && rx_has("R 0x1234abcd", 12), "   ADP W/R of DMEM 0x8001_0000");
    check(dut.soc.uncore.ram_d.mem[0] === 32'h1234abcd, "   DMEM word 0 really written (backdoor check)");

    // 3. Halt / resume -> LED0
    clear_rx(); adp_send("C 0202", 6); wait_prompt(200_000, seen);
    check(led[0] === 1'b1, "3. C 0202 halts the core -> LED0 on");
    clear_rx(); adp_send("C 0102", 6); wait_prompt(200_000, seen);
    check(led[0] === 1'b0, "   C 0102 resumes the core -> LED0 off");

    // 4. CPU_RESET button -> banner again
    clear_rx(); press_cpu_reset();
    wait_prompt(400_000, seen);
    check(seen && rx_has("0x50c1ab04", 10), "4. CPU_RESET (SW20) -> banner again");

    // 5. boot_mode DIP (SW13.2) = 1, reset -> strap latched; current boot ROM mode 1 uses SPI
    dip1 = 1'b1; cs_low_cycles = 0; sclk_edges = 0;
    press_cpu_reset();
    repeat (60_000) @(posedge clk);
    check(led[3] === 1'b1, "5. SW13.2 boot_mode -> LED3 on");
    check(dut.soc.uncore.boot_mode_latched === 1'b1, "   SYSCTRL latched boot_mode = 1");
    check(cs_low_cycles > 0 && sclk_edges > 16, "   boot ROM drives SPI CS_n/SCLK on PMOD0_0/PMOD0_3");
    check(led[6] === 1'b1, "   LED6 SPI activity");
    $display("      CS low for %0d cycles, %0d SCLK edges", cs_low_cycles, sclk_edges);

    // 6. dbg_sel DIP (SW13.1) -> LED1
    dip0 = 1'b1; repeat (5) @(posedge clk);
    check(led[1] === 1'b1 && dut.soc.dbg_sel === 1'b1, "6. SW13.1 dbg_sel -> LED1 on, SoC dbg_sel = 1");
    dip0 = 1'b0;

    // 7. Application UART on PMOD1, heartbeat
    pmod1_0 = 1'b0; #1;
    check(dut.soc.UARTSin === 1'b0, "7. PMOD1_0 (J87.1) reaches the SoC UARTSin");
    pmod1_0 = 1'b1; #1;
    check(dut.soc.UARTSin === 1'b1 && pmod1_1 === dut.soc.UARTSout, "   UARTSout drives PMOD1_1 (J87.3)");
    hb0 = dut.heartbeat; repeat (10) @(posedge clk); #1;   // sample after the edge update
    check(dut.heartbeat == hb0 + 10, "   heartbeat counter running (LED7)");

    $display("=== RESULT: %0s (%0d failures) ===", fails ? "FAILED" : "ALL PASS", fails);
    $finish;
  end

  initial begin #300_000_000; $display("TIMEOUT"); $finish; end
endmodule
