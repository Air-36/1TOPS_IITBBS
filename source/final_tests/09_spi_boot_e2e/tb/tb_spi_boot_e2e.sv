// =============================================================================
// tb_spi_boot_e2e.sv - Subsystem 09: SPI boot flow, end to end
//
// The real SoC (riscv_soc_ahb) with its DEFAULT reset addresses (system / SYSCTRL soft reset ->
// boot ROM 0x0000_1000, debugger core reset -> instruction RAM 0x8000_0000) runs the real
// generated boot ROM, which pulls a real make_image.py stream from an SPI partner model over the
// real SPI controller, copies it into RAM and jumps to it. 50 MHz clock (SPI = 250 kHz, as on
// the FPGA). The debugger UART runs at 3.125 Mbaud (16 clocks/bit) so ADP commands are fast.
//
// Plusargs:
//   +SCEN=s1|s2|s3|s4|s5|s6|s7     scenario (see README.md)
//   +STREAM=<file>                 boot stream for the partner (flash.bin format)
//   +PI_TIMED [+POLL=ns] [+LAT=ns] use the Pi 4 timed partner instead of the ideal one
// Output: [PASS]/[FAIL] lines, then "SCENARIO <name> RESULT: PASS|FAIL".
// =============================================================================
`timescale 1ns/1ps
module tb_spi_boot_e2e;
  localparam integer CLK_FREQ = 50_000_000;
  localparam integer BAUD     = 3_125_000;
  localparam integer BIT_CLKS = CLK_FREQ / BAUD;

  localparam [31:0] IRAM_BASE   = 32'h8000_0000, IRAM_END = 32'h8000_8000;
  localparam [31:0] DRAM_BASE   = 32'h8001_0000, DRAM_END = 32'h8001_8000;
  localparam [31:0] EXT_BASE    = 32'h8000_7C00;
  localparam [31:0] RESULT_ADDR = 32'h8001_4000;   // written by boot_e2e.S
  localparam [31:0] ERR_ADDR    = 32'h8001_7FFC;   // written by the loader on error
  localparam [31:0] PASS_WORD   = 32'h600D_B007;
  localparam [31:0] MAGIC_BOOT  = 32'h544F_4F42;   // "BOOT", little-endian
  localparam [31:0] ROM_PC      = 32'h0000_1000;
  localparam [31:0] RAM_PC      = 32'h8000_0000;
  localparam [31:0] SPI_BASE    = 32'h1004_0000;
  localparam [31:0] DBG_GPR_A0  = 32'h0B00_0028;   // core-debug window: x10 (a0)

  // ---------------------------------------------------------------- clock, reset, DUT
  reg clk = 1'b0;
  always #10 clk = ~clk;                           // 50 MHz
  reg reset = 1'b1;

  reg  host_tx = 1'b1;                             // terminal -> debugger
  wire dbg_tx;                                     // debugger -> terminal
  wire [3:0] SPICS;
  wire SPICLK, SPIOut, SPIIn;

  riscv_soc_ahb #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD)) soc (
    .clk(clk), .reset(reset), .boot_mode(1'b0),
    .MExtInt(1'b0), .TrapM(), .mretM(), .PCW(), .ResultW(),
    .GPIOIN(32'd0), .GPIOOUT(), .GPIOEN(), .UARTSin(1'b1), .UARTSout(),
    .SPIIn(SPIIn), .SPIOut(SPIOut), .SPICS(SPICS), .SPICLK(SPICLK),
    .dbg_sel(1'b0), .uart_rx(host_tx), .uart_tx(dbg_tx),
    .ft1248_clk(), .ft1248_ss_n(), .ft1248_miso(1'b1), .ft1248_miosio(),
    .core_halted_led()
  );

  spi_partner_model partner (.cs_n(SPICS[0]), .sclk(SPICLK), .miso(SPIIn));

  // ---------------------------------------------------------------- checks
  integer fails = 0;
  task automatic check(input bit cond, input [8*72-1:0] what);
    begin
      if (cond) $display("  [PASS] %0s", what);
      else begin $display("  [FAIL] %0s", what); fails = fails + 1; end
    end
  endtask

  // ---------------------------------------------------------------- backdoor RAM access
  function [31:0] dmem(input [31:0] a);
    dmem = soc.uncore.ram_d.mem[(a - DRAM_BASE) >> 2];
  endfunction
  task dmem_wr(input [31:0] a, input [31:0] v);
    soc.uncore.ram_d.mem[(a - DRAM_BASE) >> 2] = v;
  endtask
  function [31:0] imem(input [31:0] a);
    imem = soc.uncore.ram_i.mem[(a - IRAM_BASE) >> 2];
  endfunction
  function [7:0] ram_byte(input [31:0] a);
    reg [31:0] w;
    begin
      if (a >= IRAM_BASE && a < IRAM_END)      w = imem(a);
      else if (a >= DRAM_BASE && a < DRAM_END) w = dmem(a);
      else                                     w = 32'hxxxx_xxxx;
      ram_byte = w[8*a[1:0] +: 8];
    end
  endfunction

  // Every RAM word starts as POISON (an illegal instruction), so a boot can only succeed if the
  // loader really copied the image, and any write outside the chunks is visible afterwards.
  localparam [31:0] POISON = 32'hDEAD_10CC;
  localparam integer RAM_WORDS = 8192;               // 32 KB each
  task scrub_rams;
    integer k;
    begin
      for (k = 0; k < RAM_WORDS; k = k + 1) begin
        soc.uncore.ram_i.mem[k] = POISON;
        soc.uncore.ram_d.mem[k] = POISON;
      end
    end
  endtask

  function [31:0] gpr(input integer r);
    gpr = soc.cpu.dp.rf.reg_file_arr[r];
  endfunction

  // ---------------------------------------------------------------- observers
  // First instruction fetch after every core reset, core-reset count, fetches from the
  // second-stage ROM region, and core writes outside the RAMs / SPI block.
  // All "since the last core reset" observers are cleared while the core is in reset, so a
  // stale value from an earlier boot can never satisfy a check.
  reg     fetch_armed = 1'b1, rst_q = 1'b0, saw_ext_fetch = 1'b0, saw_rom_fetch = 1'b0;
  reg [31:0] first_fetch = 32'hFFFF_FFFF, stray_addr = 32'd0;
  reg [31:0] first_ram_fetch = 32'hFFFF_FFFF;     // first fetch from instruction RAM (any address)
  reg [31:0] first_low_fetch = 32'hFFFF_FFFF;     // first fetch from RAM below the second-stage ROM
  integer core_resets = 0, stray_writes = 0;
  always @(posedge clk) begin
    if (!rst_q && soc.core_HRESETn) core_resets = core_resets + 1;
    rst_q = soc.core_HRESETn;
    if (!soc.core_HRESETn) begin
      fetch_armed = 1'b1; first_fetch = 32'hFFFF_FFFF; first_ram_fetch = 32'hFFFF_FFFF;
      first_low_fetch = 32'hFFFF_FFFF; saw_rom_fetch = 1'b0; saw_ext_fetch = 1'b0;
    end else if (soc.core_HTRANS[1]) begin
      if (!soc.core_HWRITE) begin
        if (fetch_armed) begin first_fetch = soc.core_HADDR; fetch_armed = 1'b0; end
        if (soc.core_HADDR >= ROM_PC && soc.core_HADDR < ROM_PC + 32'h1000) saw_rom_fetch = 1'b1;
        if (soc.core_HADDR >= IRAM_BASE && soc.core_HADDR < IRAM_END && first_ram_fetch == 32'hFFFF_FFFF)
          first_ram_fetch = soc.core_HADDR;
        if (soc.core_HADDR >= IRAM_BASE && soc.core_HADDR < EXT_BASE && first_low_fetch == 32'hFFFF_FFFF)
          first_low_fetch = soc.core_HADDR;
        if (soc.core_HADDR >= EXT_BASE && soc.core_HADDR < IRAM_END) saw_ext_fetch = 1'b1;
      end else if (!((soc.core_HADDR >= IRAM_BASE && soc.core_HADDR < IRAM_END) ||
                     (soc.core_HADDR >= DRAM_BASE && soc.core_HADDR < DRAM_END) ||
                     (soc.core_HADDR >= SPI_BASE  && soc.core_HADDR < SPI_BASE + 32'h1000))) begin
        stray_writes = stray_writes + 1;
        stray_addr   = soc.core_HADDR;
      end
    end
  end

  // ---------------------------------------------------------------- terminal (debugger UART)
  reg [7:0] rxq [0:4095];
  integer   rxlen = 0, prompts = 0;
  always begin : uart_rx_monitor
    integer i; reg [7:0] c;
    @(negedge dbg_tx);
    repeat (BIT_CLKS / 2) @(posedge clk);
    if (dbg_tx == 1'b0) begin
      for (i = 0; i < 8; i = i + 1) begin repeat (BIT_CLKS) @(posedge clk); c[i] = dbg_tx; end
      repeat (BIT_CLKS) @(posedge clk);
      rxq[rxlen % 4096] = c;
      rxlen = rxlen + 1;
      if (c == "]") prompts = prompts + 1;
    end
  end

  task automatic uart_send_byte(input [7:0] b);
    integer i;
    begin
      host_tx = 1'b0; repeat (BIT_CLKS) @(posedge clk);
      for (i = 0; i < 8; i = i + 1) begin host_tx = b[i]; repeat (BIT_CLKS) @(posedge clk); end
      host_tx = 1'b1; repeat (BIT_CLKS) @(posedge clk);
    end
  endtask

  task automatic wait_prompts(input integer target, input integer max_cycles, output bit ok);
    integer t;
    begin
      ok = 0;
      for (t = 0; t < max_cycles && !ok; t = t + 1) begin
        @(posedge clk);
        if (prompts >= target) ok = 1;
      end
    end
  endtask

  function [7:0] hexch(input [3:0] n);
    hexch = (n < 10) ? ("0" + n) : ("A" + n - 10);
  endfunction

  // Send "<cmd> <8 hex digits>\r" (or "<cmd> <text>\r") and wait for the next prompt.
  task automatic adp_hex(input [7:0] cmd, input [31:0] v);
    integer i, p; bit ok;
    begin
      p = prompts;
      uart_send_byte(cmd); uart_send_byte(" ");
      for (i = 7; i >= 0; i = i - 1) uart_send_byte(hexch(v[4*i +: 4]));
      uart_send_byte(8'h0d);
      wait_prompts(p + 1, 200_000, ok);
      if (!ok) begin $display("  [FAIL] no debugger prompt after %c %08h", cmd, v); fails = fails + 1; end
    end
  endtask

  task automatic adp_text(input [8*16-1:0] s, input integer n);
    integer i, p; bit ok;
    begin
      p = prompts;
      for (i = n - 1; i >= 0; i = i - 1) uart_send_byte(s[8*i +: 8]);
      uart_send_byte(8'h0d);
      wait_prompts(p + 1, 200_000, ok);
      if (!ok) begin $display("  [FAIL] no debugger prompt after a command"); fails = fails + 1; end
    end
  endtask

  function [3:0] hexval(input [7:0] c);
    hexval = (c >= "0" && c <= "9") ? c - "0" :
             (c >= "a" && c <= "f") ? c - "a" + 10 :
             (c >= "A" && c <= "F") ? c - "A" + 10 : 4'h0;
  endfunction

  // What you would type on the bench: "A <addr>" then "R", and read "R 0x<value>".
  task automatic adp_read(input [31:0] addr, output [31:0] v);
    integer i, j, start; bit found;
    begin
      adp_hex("A", addr);
      start = rxlen;
      adp_text("R", 1);
      v = 32'hDEAD_DEAD; found = 0;
      for (i = start; i + 10 <= rxlen && !found; i = i + 1)
        if (rxq[i % 4096] == "0" && rxq[(i + 1) % 4096] == "x") begin
          v = 0;
          for (j = 0; j < 8; j = j + 1) v = {v[27:0], hexval(rxq[(i + 2 + j) % 4096])};
          found = 1;
        end
      if (!found) begin $display("  [FAIL] could not parse the R reply"); fails = fails + 1; end
    end
  endtask

  // ---------------------------------------------------------------- boot helpers
  task clear_marks;
    begin dmem_wr(RESULT_ADDR, 32'd0); dmem_wr(ERR_ADDR, 32'd0); end
  endtask

  task automatic system_reset;
    bit ok; integer p;
    begin
      p = prompts;
      reset = 1'b1; repeat (20) @(posedge clk); reset = 1'b0;
      wait_prompts(p + 1, 400_000, ok);              // debugger banner + prompt again
      if (!ok) begin $display("  [FAIL] no debugger banner after system reset"); fails = fails + 1; end
    end
  endtask

  // outcome: 1 program passed, 2 program reported a mismatch, 3 loader error word set, 0 timeout
  task automatic wait_boot(input integer max_us, output integer outcome);
    integer t; reg [31:0] r, e;
    begin
      outcome = 0;
      for (t = 0; t < max_us && outcome == 0; t = t + 1) begin
        repeat (50) @(posedge clk);                  // 1 us
        r = dmem(RESULT_ADDR); e = dmem(ERR_ADDR);
        if (r === PASS_WORD)                              outcome = 1;
        else if (r[31:20] === 12'hBAD)                    outcome = 2;
        else if (e === 32'h0000_00E1 || e === 32'h0000_00E2) outcome = 3;
      end
      repeat (200) @(posedge clk);                   // let the loader finish releasing CS
    end
  endtask

  // Independent oracle (does not trust the test program): walk the stream held by the partner
  // exactly as the loader should, compare every chunk byte with RAM, and check that every RAM
  // word outside the chunks (except the result / error words) is still POISON.
  reg     cov_i [0:8191];
  reg     cov_d [0:8191];
  integer o_mism, o_over, o_images;
  reg [31:0] o_entry [0:1];
  function [31:0] srd32(input integer off);
    srd32 = {partner.byte_at(off + 3), partner.byte_at(off + 2), partner.byte_at(off + 1), partner.byte_at(off)};
  endfunction
  task automatic verify_ram_against_stream;
    integer off, k, b;
    reg [31:0] addr, size, a;
    bit done_img;
    begin
      o_mism = 0; o_over = 0; o_images = 0; o_entry[0] = 32'hFFFF_FFFF; o_entry[1] = 32'hFFFF_FFFF;
      for (k = 0; k < RAM_WORDS; k = k + 1) begin cov_i[k] = 1'b0; cov_d[k] = 1'b0; end
      off = 0;
      while (off + 4 <= partner.len && o_images < 2) begin
        if (srd32(off) != MAGIC_BOOT) begin
          $display("  oracle: no BOOT magic at stream offset %0d", off); o_mism = o_mism + 1; off = partner.len;
        end else begin
          off = off + 4; done_img = 0;
          while (!done_img && off + 8 <= partner.len) begin
            addr = srd32(off); size = srd32(off + 4); off = off + 8;
            if (size == 0) begin o_entry[o_images] = addr; done_img = 1; end
            else begin
              for (b = 0; b < size; b = b + 1) begin
                a = addr + b;
                if (ram_byte(a) !== partner.byte_at(off + b)) begin
                  if (o_mism < 4) $display("  oracle: RAM %08h = %02h, stream byte %0d = %02h",
                                           a, ram_byte(a), off + b, partner.byte_at(off + b));
                  o_mism = o_mism + 1;
                end
                if (a >= IRAM_BASE && a < IRAM_END) cov_i[(a - IRAM_BASE) >> 2] = 1'b1;
                if (a >= DRAM_BASE && a < DRAM_END) cov_d[(a - DRAM_BASE) >> 2] = 1'b1;
              end
              off = off + size;
            end
          end
          o_images = o_images + 1;
        end
      end
      for (k = 0; k < RAM_WORDS; k = k + 1) begin
        if (!cov_i[k] && soc.uncore.ram_i.mem[k] !== POISON) begin
          if (o_over < 4) $display("  oracle: IRAM %08h changed outside the chunks: %08h", IRAM_BASE + 4*k, soc.uncore.ram_i.mem[k]);
          o_over = o_over + 1;
        end
        if (!cov_d[k] && (DRAM_BASE + 4*k) != RESULT_ADDR && (DRAM_BASE + 4*k) != ERR_ADDR &&
            soc.uncore.ram_d.mem[k] !== POISON) begin
          if (o_over < 4) $display("  oracle: DRAM %08h changed outside the chunks: %08h", DRAM_BASE + 4*k, soc.uncore.ram_d.mem[k]);
          o_over = o_over + 1;
        end
      end
    end
  endtask

  // RAM words that are no longer POISON (result / error words excluded): 0 after a rejected boot.
  function integer ram_touched;
    integer k, n;
    begin
      n = 0;
      for (k = 0; k < RAM_WORDS; k = k + 1) begin
        if (soc.uncore.ram_i.mem[k] !== POISON) n = n + 1;
        if ((DRAM_BASE + 4*k) != RESULT_ADDR && (DRAM_BASE + 4*k) != ERR_ADDR &&
            soc.uncore.ram_d.mem[k] !== POISON) n = n + 1;
      end
      ram_touched = n;
    end
  endfunction

  // Call BEFORE the reset that starts a boot: the boot ROM opens its first CS window a few
  // microseconds after reset, long before the debugger banner is complete.
  integer w_base = 0, c_base = 0, p_base = 0;
  task begin_boot;
    begin w_base = partner.windows; c_base = partner.clocked; p_base = partner.partial; end
  endtask

  // A complete, successful boot of the stream currently loaded in the partner.
  task automatic boot_and_check(input bit mode1, input [8*12-1:0] tag);
    integer outcome, w0;
    begin
      w0 = w_base;
      wait_boot(80_000, outcome);
      $display("  %0s: outcome=%0d result=%08h err=%08h ptr=%0d/%0d windows=%0d first_fetch=%08h",
               tag, outcome, dmem(RESULT_ADDR), dmem(ERR_ADDR), partner.ptr, partner.len,
               partner.windows - w0, first_fetch);
      check(outcome == 1,                      "test program ran and reported PASS (0x600DB007)");
      check(first_fetch == ROM_PC,             "first fetch after reset was the boot ROM (0x0000_1000)");
      check(dmem(ERR_ADDR) == 32'd0,           "loader error word untouched");
      check(partner.ptr == partner.len,        "whole stream consumed (partner pointer = length)");
      // Mode 1: the internal ROM releases CS (CSMODE=AUTO) and the second-stage ROM re-asserts it
      // (HOLD) ~100 cycles later. The SPI controller's state machine only advances on SCLK ticks
      // (every SCKDIV+1 = 100 cycles), so CS may stay low across the hand-over: 1 or 2 windows are
      // both correct under rules R1/R2 (bytes stay aligned; the pointer continues).
      if (mode1)
        check(partner.windows - w0 == 1 || partner.windows - w0 == 2,
              "1 or 2 CS windows (CS may stay low across the ROM hand-over)");
      else
        check(partner.windows - w0 == 1, "one CS window");
      check(SPICS[0] == 1'b1,                  "chip-select released after the boot");
      check(saw_ext_fetch == mode1,
            mode1 ? "second-stage ROM executed at 0x8000_7C00" : "second-stage ROM region never executed");
      check(stray_writes == 0,                 "no core writes outside the RAMs / SPI block");
      check(partner.clocked - c_base == partner.len,
            "SoC clocked exactly the stream length (no over-read / under-read)");
      check(partner.partial == p_base,         "no byte cut short by chip-select");
      verify_ram_against_stream();
      check(o_images == (mode1 ? 2 : 1) && o_mism == 0,
            "oracle: every chunk byte in RAM equals the stream (byte-for-byte)");
      check(o_over == 0,                       "oracle: no RAM word outside the chunks was written");
      check(first_ram_fetch == o_entry[0],     "first RAM fetch = entry address of the first image");
      if (mode1)
        check(first_low_fetch == o_entry[1],   "first test-area fetch = entry address of the test image");
    end
  endtask

  // ---------------------------------------------------------------- scenarios
  reg [8*16-1:0]  scen;
  reg [8*256-1:0] stream;
  integer outcome, w0, p, cr0, poll, lat;
  reg [31:0] v, expect_magic, bad_addr, bad_size;

  initial begin
    if (!$value$plusargs("SCEN=%s", scen))     scen   = "s1";
    if (!$value$plusargs("STREAM=%s", stream)) stream = "mode0.bin";
    if ($test$plusargs("PI_TIMED")) begin
      partner.timed = 1'b1;
      if ($value$plusargs("POLL=%d", poll)) partner.poll_ns = poll;
      if ($value$plusargs("LAT=%d", lat))   partner.lat_ns  = lat;
    end
    $display("=== tb_spi_boot_e2e: scenario %0s, partner %0s (poll %0d ns, latency %0d ns) ===",
             scen, partner.timed ? "Pi-4 timed" : "ideal", partner.poll_ns, partner.lat_ns);

    #1;
    scrub_rams();
    clear_marks();
    if (scen != "s3") begin partner.load(stream); partner.reload(); end
    else              partner.disarm();

    begin_boot();
    system_reset();

    // ---- S1 / S2: one complete boot (mode 0 or mode 1 stream)
    if (scen == "s1" || scen == "s2") begin
      boot_and_check(scen == "s2", scen == "s2" ? "mode-1 boot" : "mode-0 boot");
    end

    // ---- S3: partner not armed -> bad magic, E1
    else if (scen == "s3") begin
      wait_boot(20_000, outcome);
      check(outcome == 3 && dmem(ERR_ADDR) == 32'hE1, "loader stopped with error 0xE1 (bad magic)");
      check(gpr(10) == 32'hFFFF_FFFF,          "received magic (a0) = 0xFFFFFFFF (nothing driving MISO)");
      check(first_fetch == ROM_PC,             "first fetch was the boot ROM");
      check(SPICS[0] == 1'b1,                  "chip-select released after the error");
      check(stray_writes == 0,                 "no core writes outside the RAMs / SPI block");
      check(ram_touched() == 0,                "nothing was copied into RAM");
      adp_read(ERR_ADDR, v);
      check(v == 32'hE1,                       "debugger: A 80017FFC / R reads 0x000000E1 (bench procedure)");
      adp_read(DBG_GPR_A0, v);
      check(v == 32'hFFFF_FFFF,                "debugger: A 0B000028 / R reads a0 = 0xFFFFFFFF");
    end

    // ---- S4: a first chunk that breaks a bounds rule (make_bad_stream.py kinds) -> E2
    else if (scen == "s4") begin
      bad_addr = srd32(4);                           // the rejected header, as the partner sends it
      bad_size = srd32(8);
      $display("  first chunk header in the stream: %08h + %08h", bad_addr, bad_size);
      wait_boot(20_000, outcome);
      check(outcome == 3 && dmem(ERR_ADDR) == 32'hE2, "loader stopped with error 0xE2 (bad chunk)");
      check(gpr(8) == bad_addr,                "s0 holds the rejected chunk address");
      check(gpr(9) == bad_size,                "s1 holds the rejected chunk size");
      check(dmem(RESULT_ADDR) == 32'd0,        "test program never ran");
      check(ram_touched() == 0,                "nothing was copied into RAM (rejected before the copy)");
      check(SPICS[0] == 1'b1,                  "chip-select released after the error");
      check(stray_writes == 0,                 "no core writes outside the RAMs / SPI block");
    end

    // ---- S5: boot, then debugger core reset -> restarts in RAM, boot ROM / SPI not used
    else if (scen == "s5") begin
      boot_and_check(1'b0, "mode-0 boot");
      $display("  -- debugger core reset: C 0201 / C 0101");
      dmem_wr(RESULT_ADDR, 32'd0);
      w0 = partner.windows; cr0 = core_resets;
      adp_text("C 0201", 6);
      adp_text("C 0101", 6);
      wait_boot(5_000, outcome);
      check(core_resets == cr0 + 1,            "the core went through one reset");
      check(first_fetch == RAM_PC,             "first fetch after the debugger reset was RAM (0x8000_0000)");
      check(!saw_rom_fetch,                    "no instruction fetched from the boot ROM after the debugger reset");
      check(partner.windows == w0,             "no SPI activity: the boot ROM did not run");
      check(outcome == 1,                      "program re-ran from RAM and reported PASS again");
      check(stray_writes == 0,                 "no core writes outside the RAMs / SPI block");
    end

    // ---- S6: boot, then SYSCTRL soft core reset -> back through the boot ROM, boots again
    else if (scen == "s6") begin
      boot_and_check(1'b0, "mode-0 boot");
      $display("  -- partner reloaded, SYSCTRL soft core reset: 0x1008_0000 <= 2, then 3");
      partner.reload();
      dmem_wr(RESULT_ADDR, 32'd0);
      cr0 = core_resets;
      adp_hex("A", 32'h1008_0000); adp_hex("W", 32'h0000_0002);   // core reset on, peripherals running
      scrub_rams(); clear_marks();                   // core held in reset: wipe boot 1's image
      begin_boot();
      adp_hex("A", 32'h1008_0000); adp_hex("W", 32'h0000_0003);   // release (W auto-increments A)
      boot_and_check(1'b0, "boot after soft reset");
      check(core_resets == cr0 + 1,            "the core went through one reset");
    end

    // ---- S7: rule R4 - a SoC reset does not rewind the partner
    else if (scen == "s7") begin
      boot_and_check(1'b0, "mode-0 boot");
      $display("  -- S7a: system reset WITHOUT reloading (partner past the end)");
      reset = 1'b1; scrub_rams(); clear_marks();     // (system_reset re-asserts and releases)
      system_reset();
      wait_boot(20_000, outcome);
      check(outcome == 3 && dmem(ERR_ADDR) == 32'hE1, "error 0xE1: the stream was not served again");
      check(gpr(10) == 32'hFFFF_FFFF,          "received magic = 0xFFFFFFFF (partner past the end)");
      check(first_fetch == ROM_PC,             "first fetch was the boot ROM");
      check(dmem(RESULT_ADDR) == 32'd0,        "the old program did not run again");

      $display("  -- S7b: reload, reset in the middle of the load, no reload");
      partner.reload();
      clear_marks();
      system_reset();
      wait (partner.ptr >= 24);                      // part of the image has been sent
      w0 = partner.windows;
      reset = 1'b1; repeat (20) @(posedge clk); reset = 1'b0;
      wait (partner.windows > w0);                   // the next boot's CS window opens
      p = partner.ptr;                               // R2: it continues from here
      expect_magic = {partner.byte_at(p + 3), partner.byte_at(p + 2), partner.byte_at(p + 1), partner.byte_at(p)};
      wait_boot(20_000, outcome);
      $display("  S7b: second window started at byte %0d, magic received %08h (expected %08h)",
               p, gpr(10), expect_magic);
      check(outcome == 3 && dmem(ERR_ADDR) == 32'hE1, "error 0xE1 after a reset in mid-load");
      check(gpr(10) == expect_magic && gpr(10) != MAGIC_BOOT,
            "received magic = the mid-stream bytes (pointer kept: R1/R2/R4)");
    end

    else begin
      $display("  [FAIL] unknown scenario %0s", scen); fails = fails + 1;
    end

    $display("SCENARIO %0s RESULT: %s (%0d failures)", scen, fails == 0 ? "PASS" : "FAIL", fails);
    $finish;
  end

  initial begin
    #400_000_000;                                  // 400 ms of simulated time
    $display("  [FAIL] global timeout");
    $display("SCENARIO %0s RESULT: FAIL (timeout)", scen);
    $finish;
  end
endmodule
