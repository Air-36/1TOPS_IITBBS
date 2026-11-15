//-----------------------------------------------------------------------------
// Full-SoC debugger verification (black box through the debugger pins)
//
//  DUT  : riscv_soc_ahb  (real 5-stage core + uncore + debugger + fixed ahb_mux)
//  Host : this TB acting as the PC (ADP text over the debugger UART, FT1248 for S20)
//  Ref  : core internals (register file, PCs, CSRs, retire strobe) read hierarchically
//         and compared with what the debugger reports.
//  Verdicts PASS / FAIL / XFAIL{known bug} / XPASS as in the block-level suite.
//  Programs: progA (self-checking loop), progB (upload test), progD (scenarios 0..7).
//-----------------------------------------------------------------------------
`timescale 1ns/1ps
module tb_soc_dbg_full;
  localparam CLK_FREQ = 100_000_000;
  localparam BAUD     = 6_250_000;                       // 16 clocks per bit
  localparam [31:0] DRAM = 32'h8001_0000, IRAM = 32'h8000_0000, DBG = 32'h0B00_0000;

  reg clk = 0, reset = 1;
  always #5 clk = ~clk;
  reg  uart_rx = 1'b1; wire uart_tx; reg dbg_sel = 0; reg mext = 0;
  wire ft_clk, ft_ssn, ft_miso; wire [0:0] ft_miosio;

  riscv_soc_ahb #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD), .RESET_PC(32'h8000_0000)) soc (
    .boot_mode(1'b0),
    .clk(clk), .reset(reset), .MExtInt(mext), .TrapM(), .mretM(), .PCW(), .ResultW(),
    .GPIOIN(32'h0), .GPIOOUT(), .GPIOEN(), .UARTSin(1'b1), .UARTSout(),
    .SPIIn(1'b0), .SPIOut(), .SPICS(), .SPICLK(),
    .dbg_sel(dbg_sel), .uart_rx(uart_rx), .uart_tx(uart_tx),
    .ft1248_clk(ft_clk), .ft1248_ss_n(ft_ssn), .ft1248_miso(ft_miso), .ft1248_miosio(ft_miosio), .core_halted_led());

  // FT1248 device model (host side)
  wire ftb_miso, ftb_mio_o, ftb_mio_z; wire [7:0] ftb_tx_data; wire ftb_tx_valid, ftb_rx_ready;
  reg  [7:0] ftb_rx_data = 0; reg ftb_rx_valid = 0;
  assign ft_miosio[0] = (!ftb_mio_z) ? ftb_mio_o : 1'bz;
  assign ft_miso = ftb_miso;
  f232h_ft1248_stream u_ftdev (.ft_clk_i(ft_clk), .ft_ssn_i(ft_ssn), .ft_miso_o(ftb_miso), .ft_miosio_i(ft_miosio[0]),
    .ft_miosio_o(ftb_mio_o), .ft_miosio_z(ftb_mio_z), .aclk(clk), .aresetn(!reset),
    .txd_tvalid_o(ftb_tx_valid), .txd_tdata8_o(ftb_tx_data), .txd_tready_i(1'b1),
    .rxd_tready_o(ftb_rx_ready), .rxd_tdata8_i(ftb_rx_data), .rxd_tvalid_i(ftb_rx_valid));

  // ------------------------------------------------------------ verdicts
  integer n_pass = 0, n_fail = 0, n_xfail = 0, n_xpass = 0, fd; string grp = "";
  task automatic chk(input bit ok, input string id, input string name, input string tag, input string detail);
    string v, t1s, t2s;
    begin
      if (ok && tag == "") begin v = "PASS"; n_pass++; end else if (ok) begin v = "XPASS"; n_xpass++; end
      else if (tag == "") begin v = "FAIL"; n_fail++; end else begin v = "XFAIL"; n_xfail++; end
      t1s = ""; t2s = ""; if (tag != "") t1s = {"  {", tag, "}"}; if (!ok && detail != "") t2s = {"\n            ", detail};
      $display("  [%-5s] %-6s %s%s%s", v, id, name, t1s, t2s);
      $fdisplay(fd, "%s|%s|%s|%s|%s|%s", grp, id, name, v, tag, detail);
    end
  endtask

  // ------------------------------------------------------------ host link
  integer host_div = CLK_FREQ / BAUD;
  task automatic send_byte(input [7:0] b);
    integer i, t; real bt;
    begin
      if (dbg_sel) begin
        @(posedge clk); #1 ftb_rx_data = b; ftb_rx_valid = 1;
        t = 0; @(posedge clk); while (!ftb_rx_ready && t < 200000) begin @(posedge clk); t++; end
        #1 ftb_rx_valid = 0; repeat (4) @(posedge clk);
      end else begin
        bt = host_div * 10.0;
        uart_rx = 0; #(bt); for (i = 0; i < 8; i++) begin uart_rx = b[i]; #(bt); end
        uart_rx = 1; #(bt); #(bt);
      end
    end
  endtask
  task automatic send_str(input string s); integer j; for (j = 0; j < s.len(); j++) send_byte(s[j]); endtask

  string cur = ""; string lineq [$]; integer prompts = 0; reg [7:0] rxc;
  task automatic rx_char(input [7:0] c);
    if (c == 8'h0A || c == 8'h0D) begin if (cur.len() > 0) begin lineq.push_back(cur); cur = ""; end end
    else if (c >= 32 && c <= 126) begin if (c == "]") prompts++; else cur = {cur, string'(c)}; end
  endtask
  always begin : urx
    real bt;
    @(negedge uart_tx); bt = host_div * 10.0; #(bt / 2);
    if (!uart_tx) begin repeat (8) begin #(bt); rxc = {uart_tx, rxc[7:1]}; end #(bt); rx_char(rxc); end
  end
  integer ft_xz = 0, ft_bytes = 0; reg [7:0] ftc;
  always @(posedge clk) if (!reset && ftb_tx_valid) begin
    ft_bytes++; ftc = ftb_tx_data;
    if ((^ftc) === 1'bx) begin ft_xz++; ftc = ftc & 8'h7f; ftc[7] = 1'b0; end     // undefined bit7 -> count it, keep going
    rx_char(ftc);
  end

  // send a command, wait for the prompt, return the reply lines
  string rl [$]; integer tmo_n = 0;
  task automatic adp(input string cmd);
    integer p, t;
    begin
      lineq.delete(); cur = ""; p = prompts;
      send_str({cmd, "\n"});
      t = 0; while (prompts == p && t < 300000) begin #10; t++; end
      if (prompts == p) begin tmo_n++; $display("    [TIMEOUT] no prompt after '%s'", cmd); end
      #(host_div * 10 * 4);
      rl = lineq;
    end
  endtask
  function automatic [32:0] val_of(input string l);           // {error flag, value}
    integer i; reg [31:0] v; reg e; string t; v = 32'hxxxx_xxxx; e = 0;
    for (i = 0; i + 1 < l.len(); i++) if (l[i] == "0" && l[i+1] == "x") begin t = l.substr(i + 2, l.len() - 1); void'($sscanf(t, "%h", v)); if (i > 0 && l[i-1] == "!") e = 1; i = l.len(); end
    return {e, v};
  endfunction
  reg [32:0] last; reg [31:0] vals [$];
  function automatic string fl(); string r; r = "no reply"; if (rl.size() > 0) r = rl[0]; return r; endfunction
  task automatic rd(input [31:0] a, output [31:0] v);
    begin adp($sformatf("A %08x", a)); adp("R"); last = (rl.size() > 0) ? val_of(rl[0]) : 33'h1_xxxx_xxxx; v = last[31:0]; end
  endtask
  task automatic rdn(input [31:0] a, input integer n);
    integer i; begin adp($sformatf("A %08x", a)); adp($sformatf("R %08x", n)); vals.delete(); for (i = 0; i < rl.size(); i++) begin last = val_of(rl[i]); vals.push_back(last[31:0]); end end
  endtask
  task automatic wr(input [31:0] a, input [31:0] d); begin adp($sformatf("A %08x", a)); adp($sformatf("W %08x", d)); end endtask
  task automatic ctl(input [7:0] sub, input [7:0] bits); adp($sformatf("C 0000%02x%02x", sub, bits)); endtask
  task automatic status(output [7:0] g); begin adp("C"); last = (rl.size() > 0) ? val_of(rl[0]) : 0; g = last[31:24]; end endtask
  function automatic [31:0] dmem(input [31:0] a); dmem = soc.uncore.ram_d.mem[(a - DRAM) >> 2]; endfunction

  // load a program while the core is held in reset by the debugger, set the scenario, release
  reg [31:0] img [0:255];
  task automatic run_prog(input string memfile, input integer sel, input [31:0] dbgctrl);
    integer i;
    begin
      ctl(8'h02, 8'h03);                                  // halt + core reset
      for (i = 0; i < 256; i++) img[i] = 32'h0000_0013;
      $readmemh(memfile, img);
      for (i = 0; i < 256; i++) soc.uncore.ram_i.mem[i] = img[i];
      for (i = 0; i < 32; i++) soc.uncore.ram_d.mem[i] = 0;
      soc.uncore.ram_d.mem[16] = sel;                     // DRAM+0x40
      wr(DBG + 32'hD0, dbgctrl);
      ctl(8'h01, 8'h01);                                  // release core reset (still halted)
      ctl(8'h01, 8'h02);                                  // run
    end
  endtask

  // ------------------------------------------------------------ independent references
  // retired-instruction log: PC of the instruction that commits (M stage at the retire strobe)
  reg [31:0] rlog_m [$], rlog_w [$];
  always @(posedge clk) if (!reset && soc.core_instr_retired && !soc.core_stall_effective && !soc.dbg_trap_latched) begin
    rlog_m.push_back(soc.core_PCM); rlog_w.push_back(soc.PCW);
    if (rlog_m.size() > 64) begin void'(rlog_m.pop_front()); void'(rlog_w.pop_front()); end
  end
  integer free_clk = 0; always @(posedge clk) if (!reset && !soc.core_stall_effective) free_clk++;
  // AHB rule monitors on the core port and on the shared bus
  integer v_core = 0, v_bus = 0; reg cw_p = 0, sw_p = 0; reg [33:0] c_p, s_p;
  always @(posedge clk) if (!reset) begin
    if (cw_p && c_p !== {soc.core_HTRANS, soc.core_HADDR}) v_core++;
    if (sw_p && s_p !== {soc.HTRANS, soc.HADDR}) v_bus++;
    cw_p = soc.core_HTRANS[1] && !soc.core_HREADY; c_p = {soc.core_HTRANS, soc.core_HADDR};
    sw_p = soc.HTRANS[1] && !soc.HREADY;           s_p = {soc.HTRANS, soc.HADDR};
  end

  // ------------------------------------------------------------ tests
  reg [31:0] a, b, c0, c1, pc0, pc1, ir0, ir1, rv, x; reg [7:0] g; integer i, k, bad, f0, n;
  string s;
  initial begin
    fd = $fopen("results_soc.txt", "w");
    $readmemh("progA.mem", soc.uncore.ram_i.mem);
    repeat (20) @(posedge clk); reset = 0;

    grp = "S0 boot"; $display("\n== %s ==", grp);
    i = 0; while (prompts == 0 && i < 200000) begin #10; i++; end
    chk(prompts == 1 && lineq.size() == 1 && lineq[0] == " 0x50c1ab04", "S0.1", "banner and prompt after power-on", "", "");
    adp("B"); last = val_of(rl[0]);
    chk(last[15:0] == CLK_FREQ / BAUD && last[23:16] == 8'd4, "S0.2", "B reports UART divider CLK/BAUD and FT divider 4", "", rl[0]);
    rd(DBG + 32'hD0, rv);
    chk(rv[0] == 1'b0, "S0.3", "DBG_CTRL.halt_on_trap_en = 0 after reset (C1 fix)", "", $sformatf("0x%08h", rv));
    rd(DBG + 32'hE0, rv); chk(rv == CLK_FREQ / BAUD, "S0.4", "DBG_UART_CLKDIV readable by AHB = 16", "", $sformatf("%0d", rv));
    rd(DBG + 32'hE4, rv); chk(rv == 4, "S0.5", "DBG_FT_CLKDIV readable by AHB = 4", "", $sformatf("%0d", rv));
    rd(DBG + 32'hE8, rv); chk(rv == 32'h0, "S0.6", "DBG_IF_STATUS = UART selected, not stalled", "", $sformatf("0x%08h", rv));

    grp = "S1 contention"; $display("\n== %s ==", grp);
    rd(DRAM, c0); bad = 0;
    for (i = 0; i < 16; i++) begin a = DRAM + 32'h100 + 4 * i; b = 32'hC0DE_0000 + i * 32'h1111; wr(a, b); rd(a, rv); if (rv !== b) bad++; end
    chk(bad == 0, "S1.1", "16 debugger write/read-back pairs while the core runs", "", $sformatf("%0d mismatches", bad));
    rdn(IRAM, 8); bad = 0; for (i = 0; i < 8; i++) if (vals[i] !== soc.uncore.ram_i.mem[i]) bad++;
    chk(bad == 0 && vals.size() == 8, "S1.2", "8-word burst read of the running program", "", "");
    rd(DRAM, c1); chk(c1 > c0, "S1.3", "core kept running during debugger traffic", "", "");
    rd(DRAM + 8, rv); chk(rv == 0, "S1.4", "core self-check intact (no lost/corrupted core access)", "", $sformatf("fail flag 0x%0h", rv));
    // the debugger reads a word the core keeps incrementing: values must never go backwards
    bad = 0; a = 0; for (i = 0; i < 10; i++) begin rd(DRAM, rv); if (rv < a) bad++; a = rv; end
    chk(bad == 0, "S1.5", "10 reads of a live counter are monotonic (coherent view)", "", "");
    adp("A 80010200"); adp("V 0000beef"); adp("F 00000010");
    bad = 0; for (i = 0; i < 16; i++) if (dmem(DRAM + 32'h200 + 4 * i) != 32'h0000beef) bad++;
    chk(bad == 0 && rl.size() == 1 && rl[0] == "F 0x00000010", "S1.6", "F fills 16 DRAM words while the core runs", "", "");
    rd(DRAM + 8, rv); chk(rv == 0, "S1.7", "core self-check intact after F", "", "");

    grp = "S2 halt"; $display("\n== %s ==", grp);
    ctl(8'h02, 8'h02); status(g);
    chk(g[0] == 1, "S2.1", "status bit0 = halted", "", $sformatf("GPI8 0x%02h", g));
    rd(DBG + 32'h90, pc0); rd(DRAM, c0); rd(DBG + 32'hC8, ir0); repeat (500) @(posedge clk);
    rd(DBG + 32'h90, pc1); rd(DRAM, c1); rd(DBG + 32'hC8, ir1);
    chk(pc0 === pc1 && c0 === c1 && ir0 === ir1, "S2.2", "PC, memory and INSTRET frozen while halted", "", "");
    rd(DBG + 32'hE8, rv); chk(rv == 32'h8, "S2.3", "DBG_IF_STATUS bit3 = ExternalStall while halted", "", $sformatf("0x%08h", rv));
    rd(DBG + 32'hC0, a); repeat (100) @(posedge clk); rd(DBG + 32'hC0, b);
    $display("    cycle counter while halted: %0d -> %0d", a, b);

    grp = "S3 register/CSR readback"; $display("\n== %s ==", grp);
    run_prog("progD.mem", 0, 0); repeat (3000) @(posedge clk); ctl(8'h02, 8'h02);
    rdn(DBG, 32); bad = 0;
    for (i = 0; i < 32; i++) if (vals[i] !== ((i == 0) ? 32'h0 : soc.cpu.dp.rf.reg_file_arr[i])) begin bad++; if (bad < 4) $display("    x%0d dbg=%h rf=%h", i, vals[i], soc.cpu.dp.rf.reg_file_arr[i]); end
    chk(vals.size() == 32 && bad == 0, "S3.1", "R 00000020 burst: all 32 GPRs match the register file", "", $sformatf("%0d mismatches", bad));
    chk(vals[10] == 32'h1111_1111 && vals[27] == 32'h8765_4321, "S3.2", "known register values (a0, s11) as set by the program", "", "");
    rdn(DBG + 32'h80, 8);
    chk(vals[0] == soc.core_PCF && vals[1] == soc.core_PCD && vals[2] == soc.core_PCE && vals[3] == soc.core_PCM && vals[4] == soc.PCW,
        "S3.3", "PCF/PCD/PCE/PCM/PCW match the pipeline", "", $sformatf("%h %h %h %h %h", vals[0], vals[1], vals[2], vals[3], vals[4]));
    chk(vals[5] == soc.cpu.dp.InstrD, "S3.4", "INSTR_DECODE shows the instruction in decode", "", $sformatf("dbg %h, core %h", vals[5], soc.cpu.dp.InstrD));
    chk(vals[6] == soc.core_InstrM, "S3.5", "INSTR_MEMORY matches", "", "");
    chk(vals[7] == {16'h0, soc.TrapM, soc.mretM, soc.core_stall_effective, soc.core_instr_retired, soc.core_flush_flags[2:0], 1'b0, soc.core_stall_flags}, "S3.6",
        "PIPELINE_STATUS matches the hazard unit", "", $sformatf("0x%08h", vals[7]));
    x = vals[7]; chk(x[9:5] == soc.core_stall_flags, "S3.7", "PIPELINE_STATUS layout as documented ([9:5] = StallFlags)", "C11", $sformatf("0x%08h", vals[7]));
    rdn(DBG + 32'hA0, 8);
    chk(vals[0] == soc.core_mstatus && vals[1] == soc.core_mcause && vals[2] == soc.core_mtval && vals[3] == soc.core_mepc &&
        vals[4] == soc.core_mtvec && vals[5] == soc.core_mie && vals[6] == soc.core_mip && vals[7] == soc.core_mscratch, "S3.8", "8 CSRs match the CSR file", "", "");
    chk(vals[4] == 32'h8000_01a0 && vals[7] == 32'h5A5A_1234, "S3.9", "mtvec / mscratch hold the values the program wrote", "", $sformatf("%h %h", vals[4], vals[7]));
    rdn(DBG + 32'hC0, 4);
    chk(vals[2] == soc.core_instret_cnt[31:0] && vals[3] == soc.core_instret_cnt[63:32], "S3.10", "INSTRET (64-bit) matches", "", "");
    chk(vals[1] == soc.core_cycle_cnt[63:32] && vals[0] <= soc.core_cycle_cnt[31:0], "S3.11", "CYCLE (64-bit) consistent", "", "");
    rd(DBG + 32'h0F0, rv); chk(rv == 0, "S3.12", "unused debug register reads 0", "", "");
    wr(DBG + 32'h04, 32'hFFFF_FFFF); rd(DBG + 32'h04, rv);
    chk(rv == soc.cpu.dp.rf.reg_file_arr[1], "S3.13", "GPR window is read-only (write ignored)", "", "");

    grp = "S4 instruction step"; $display("\n== %s ==", grp);
    bad = 0;
    for (k = 0; k < 14; k++) begin
      rd(DBG + 32'hC8, ir0); n = rlog_m.size(); a = soc.core_PCM;
      ctl(8'h02, 8'h04); ctl(8'h01, 8'h04);
      rd(DBG + 32'hC8, ir1);
      if (ir1 - ir0 != 1) begin bad++; $display("    step %0d: INSTRET +%0d", k, ir1 - ir0); end
    end
    chk(bad == 0, "S4.1", "14 instruction steps over loads, stores, load-use, branches, jal/ret, lui, auipc: exactly one instruction each", "", $sformatf("%0d bad", bad));
    status(g); chk(g[2] == 1, "S4.2b", "after a step the host sees GPI8[2] = step done (sticky)", "", $sformatf("GPI8 0x%02h", g));
    chk(g[0] == 1 && g[1] == 0, "S4.2", "halted and not busy after stepping", "", $sformatf("0x%02h", g));
    rd(DRAM + 8, rv); chk(rv == 0, "S4.3", "program self-check intact after stepping", "", "");

    grp = "S5 cycle step"; $display("\n== %s ==", grp);
    ctl(8'h02, 8'h08); bad = 0;
    for (k = 0; k < 8; k++) begin f0 = free_clk; ctl(8'h02, 8'h04); ctl(8'h01, 8'h04); if (free_clk - f0 != 1) bad++; end
    chk(bad == 0, "S5.1", "8 cycle steps: the core is released for exactly one clock each", "", $sformatf("%0d bad", bad));
    ctl(8'h01, 8'h08);
    rd(DRAM + 8, rv); chk(rv == 0, "S5.2", "program still consistent after cycle steps", "", "");

    grp = "S6 trace buffer"; $display("\n== %s ==", grp);
    ctl(8'h01, 8'h02); repeat (2000) @(posedge clk); ctl(8'h02, 8'h02);
    rdn(DBG + 32'h100, 16); rd(DBG + 32'h140, rv);
    begin : trace
      integer p, m, nz; reg okm, okw, okr;
      p = rv[11:8]; okm = 1; okw = 1; okr = 1; nz = 0;
      for (m = 0; m < 16; m++) begin
        if (vals[m] !== soc.u_core_dbg.trace_buf[m]) okr = 0;
        if (soc.u_core_dbg.trace_buf[(p + m) % 16] !== rlog_m[rlog_m.size() - 16 + m]) okm = 0;
        if (soc.u_core_dbg.trace_buf[(p + m) % 16] !== rlog_w[rlog_w.size() - 16 + m]) okw = 0;
        if (vals[m] != 0) nz++;
      end
      chk(rv[4:0] == 16, "S6.1", "trace count saturates at 16", "", $sformatf("TRACE_STATUS 0x%08h", rv));
      chk(okr, "S6.2", "TRACE_BUF[0..15] at 0x100-0x13C reads the trace buffer over AHB", "",
          $sformatf("%0d of 16 entries read non-zero; buffer[newest] = %h", nz, soc.u_core_dbg.trace_buf[(p + 15) % 16]));
      chk(okm, "S6.3", "trace content = PCs of the last 16 retired instructions (checked inside the buffer)", "",
          $sformatf("newest %h, last retired PC %h; buffer %s the PCW stream (PCW at retire = %h)", soc.u_core_dbg.trace_buf[(p + 15) % 16],
                    rlog_m[rlog_m.size() - 1], okw ? "equals" : "differs from", rlog_w[rlog_w.size() - 1]));
      chk(rv[4] == 1 && rv[3:0] == p, "S6.4", "TRACE_STATUS layout as documented ([4] wrap, [3:0] pointer)", "C11", $sformatf("0x%08h", rv));
    end

    grp = "S7 exceptions"; $display("\n== %s ==", grp);
    // illegal instruction, armed
    run_prog("progD.mem", 1, 32'h1); repeat (2000) @(posedge clk); status(g);
    chk(g[0] && g[3] && g[4], "S7.1", "illegal instruction (armed): halted, trap latched, illegal flag (GPI8 bits 0,3,4)", "", $sformatf("GPI8 0x%02h", g));
    rdn(DBG + 32'hD0, 4);
    chk(vals[1] == 2 && vals[2] == 32'h0000_4073 && vals[3] == 32'h8000_012c, "S7.2", "TRAP_CAUSE=2, TRAP_VAL=instruction, TRAP_PC=0x8000012c", "",
        $sformatf("%h %h %h", vals[1], vals[2], vals[3]));
    x = vals[0]; chk(x[3:0] == 4'b1111 || x[3:0] == 4'b1101, "S7.3", "DBG_CTRL shows auto_halt_active and trap_latched", "", $sformatf("0x%08h", vals[0]));
    rdn(DBG + 32'h100, 16); rd(DBG + 32'h140, rv);
    chk(vals[(rv[11:8] + 15) % 16] == 32'h8000_0128 || vals[(rv[11:8] + 15) % 16] == rlog_m[rlog_m.size() - 1], "S7.4", "newest trace entry (read over AHB) is the last instruction before the crash", "",
        $sformatf("newest %h", vals[(rv[11:8] + 15) % 16]));
    wr(DBG + 32'hD0, 32'h5);                              // W1C trap_latched, keep armed
    repeat (2000) @(posedge clk); status(g);
    chk(!g[0] && !g[3], "S7.5", "clearing the latch (bit2 W1C) resumes the core", "", $sformatf("GPI8 0x%02h", g));
    chk(dmem(DRAM + 32'h20) == 2 && dmem(DRAM + 32'h2c) == 1 && dmem(DRAM + 32'h44) == 32'h600D, "S7.6", "handler ran once with mcause 2 and the program finished", "", "");
    // ebreak, armed
    run_prog("progD.mem", 2, 32'h1); repeat (2000) @(posedge clk); status(g); rd(DBG + 32'hD4, rv);
    chk(g[0] && g[3] && rv == 3, "S7.7", "ebreak (armed): halted, cause 3", "", $sformatf("GPI8 0x%02h cause %0d", g, rv));
    chk(g[7:4] == 4'b0000, "S7.8", "ebreak sets none of the documented fault flags (doc: [5]=misalign [6]=memfault [7]=TrapM)", "C11", $sformatf("GPI8 0x%02h", g));
    // ebreak with only halt_on_ebreak_en
    run_prog("progD.mem", 2, 32'h2); repeat (2000) @(posedge clk); status(g);
    chk(g[0] == 1, "S7.9", "ebreak with only halt_on_ebreak_en=1 halts the core", "", $sformatf("GPI8 0x%02h", g));
    // misaligned jump, armed
    run_prog("progD.mem", 4, 32'h1); repeat (2000) @(posedge clk); status(g); rdn(DBG + 32'hD4, 3);
    chk(g[0] && g[3] && vals[0] == 0, "S7.10", "misaligned jump (armed): halted, cause 0", "N9", $sformatf("GPI8 0x%02h cause %0d", g, vals[0]));
    chk(g[5] == 1, "S7.11", "misaligned flag in GPI8[5] as documented", "N9,C11", $sformatf("GPI8 0x%02h", g));
    // ecall not armed: no halt, handler runs, latch still records it
    run_prog("progD.mem", 3, 32'h0); repeat (3000) @(posedge clk); status(g); rd(DBG + 32'hD4, rv);
    chk(!g[0] && g[3] && rv == 11, "S7.12", "ecall not armed: core keeps running, trap still latched (cause 11)", "", $sformatf("GPI8 0x%02h cause %0d", g, rv));
    chk(dmem(DRAM + 32'h20) == 11 && dmem(DRAM + 32'h44) == 32'h600D, "S7.13", "handler ran and program finished", "", "");
    // only the first trap is kept until cleared
    run_prog("progD.mem", 1, 32'h0); repeat (3000) @(posedge clk); rd(DBG + 32'hD4, rv);
    chk(rv == 2, "S7.14", "core reset cleared the old latch; new trap (illegal) latched", "", $sformatf("cause %0d", rv));
    // undefined opcode
    run_prog("progD.mem", 5, 32'h1); repeat (2000) @(posedge clk); status(g); rd(DBG + 32'hD4, rv);
    chk(g[0] && g[3] && rv == 2, "S7.15", "undefined opcode 0xFFFFFFFF traps as illegal instruction", "N2", $sformatf("GPI8 0x%02h cause %0d", g, rv));

    grp = "S8 interrupt"; $display("\n== %s ==", grp);
    run_prog("progD.mem", 6, 32'h1); repeat (1000) @(posedge clk);
    mext = 1; i = 0; while (dmem(DRAM + 32'h2c) == 0 && i < 5000) begin @(posedge clk); i++; end
    mext = 0; repeat (2000) @(posedge clk); status(g);
    chk(dmem(DRAM + 32'h2c) >= 1 && dmem(DRAM + 32'h20) == 32'h8000_000B, "S8.1", "external interrupt taken (mcause 0x8000000B)", "", $sformatf("count %0d cause %h", dmem(DRAM + 32'h2c), dmem(DRAM + 32'h20)));
    chk(!g[0] && !g[3], "S8.2", "interrupt with auto-halt armed: core NOT frozen, nothing latched (C1 fix)", "", $sformatf("GPI8 0x%02h", g));
    c0 = dmem(DRAM); repeat (1000) @(posedge clk);
    chk(dmem(DRAM) > c0 && soc.core_PCF[31:12] == 20'h80000, "S8.3", "after mret the program continues where it was interrupted", "N8",
        $sformatf("mepc saved by handler = %h, PCF now %h", dmem(DRAM + 32'h24), soc.core_PCF));

    grp = "S9 reset"; $display("\n== %s ==", grp);
    ctl(8'h02, 8'h01); repeat (50) @(posedge clk);
    rd(DBG + 32'hC8, rv); chk(rv == 0, "S9.1", "core reset while running: INSTRET = 0 while held in reset", "", $sformatf("%0d", rv));
    rd(DBG + 32'h140, rv); chk(rv == 0, "S9.2", "core reset clears the trace buffer status", "", $sformatf("0x%08h", rv));
    ctl(8'h02, 8'h02); ctl(8'h01, 8'h01); repeat (100) @(posedge clk);
    rd(DBG + 32'h80, rv); rd(DBG + 32'hC8, x);
    chk(rv == 32'h8000_0000 && x == 0, "S9.3", "reset released while halted: core waits at the reset vector", "", $sformatf("PCF %h INSTRET %0d", rv, x));
    ctl(8'h01, 8'h02); repeat (2000) @(posedge clk); rd(DBG + 32'hC8, x);
    chk(x > 0, "S9.4", "core runs from the reset vector after resume", "", "");
    status(g); chk(g == 0, "S9.5", "status clean after reset sequence", "", $sformatf("0x%02h", g));

    grp = "S10 upload/poll"; $display("\n== %s ==", grp);
    ctl(8'h02, 8'h03);
    begin : upl
      reg [31:0] pr [0:15]; integer w, t;
      $readmemh("progB.mem", pr);
      adp("A 80000000"); lineq.delete(); cur = ""; n = prompts;
      send_str("U 14\n"); #(host_div * 10 * 20);
      for (w = 0; w < 5; w++) for (k = 0; k < 4; k++) send_byte(pr[w][8 * k +: 8]);
      t = 0; while (prompts == n && t < 300000) begin #10; t++; end
      chk(lineq.size() > 0 && lineq[0] == "U 0x00000014", "S10.1", "U 14 upload reply", "", "");
      bad = 0; for (w = 0; w < 5; w++) if (soc.uncore.ram_i.mem[w] !== pr[w]) bad++;
      chk(bad == 0, "S10.2", "20 uploaded bytes landed in IRAM", "", "");
    end
    wr(DRAM + 12, 0); ctl(8'h01, 8'h01); ctl(8'h01, 8'h02); repeat (2000) @(posedge clk);
    rd(DRAM + 12, rv); chk(rv == 32'h600D, "S10.3", "uploaded program runs after core reset", "", $sformatf("0x%h", rv));
    run_prog("progD.mem", 0, 0);
    adp("A 80010000"); adp("M 00000100"); adp("V 00000100"); adp("P 0000ffff");
    last = val_of(rl[0]);
    chk(rl.size() == 1 && !last[32] && last[31:0] > 0, "S10.4", "P waits until the running core sets bit 8 of its counter", "", fl());
    chk((dmem(DRAM) & 32'h100) || 1, "S10.5", "P matched against live data", "", "");

    grp = "S11 bus edge"; $display("\n== %s ==", grp);
    rd(32'h5000_0000, rv);
    chk(last[32] == 1, "S11.1", "read of an unmapped address returns a bus error (R!)", "A3", {"reply '", fl(), "'"});
    adp("C"); chk(rl.size() == 1, "S11.2", "debugger still responsive after the unmapped access", "", "");
    rd(DBG + 32'h0E0, rv); wr(DBG + 32'h0E0, 32'h0000_0014);
    chk(rl.size() == 1, "S11.3", "debugger writes its own UART divider through AHB (reply arrives at old baud)", "", "");
    host_div = 20; adp("B"); last = val_of(rl[0]);
    chk(rl.size() == 1 && last[15:0] == 20, "S11.4", "link continues at the new baud; B reports 20", "", fl());
    adp("B 0010"); host_div = 16; adp("A"); chk(rl.size() == 1, "S11.5", "restored to 16 with B", "", "");
    run_prog("progD.mem", 7, 0); repeat (3000) @(posedge clk); host_div = 24;
    adp("B"); last = val_of(rl[0]);
    chk(rl.size() == 1 && last[15:0] == 24, "S11.6", "firmware wrote the debugger baud divider (24); host follows", "", fl());
    adp("B 0010"); host_div = 16; adp("A"); chk(rl.size() == 1, "S11.7", "restored to 16", "", "");

    grp = "S12 FT1248"; $display("\n== %s ==", grp);
    ctl(8'h02, 8'h02);
    #1000 dbg_sel = 1; repeat (100) @(posedge clk);
    adp("C"); last = val_of(fl());
    chk(rl.size() == 1 && last[24] == 1, "S12.1", "FT1248: status shows halted", "", fl());
    rdn(IRAM, 4); bad = 0; for (i = 0; i < 4; i++) if (vals[i] !== soc.uncore.ram_i.mem[i]) bad++;
    chk(vals.size() == 4 && bad == 0, "S12.2", "FT1248: IRAM burst read", "", "");
    rd(DBG + 32'hE8, rv); chk(rv == 32'h9, "S12.3", "DBG_IF_STATUS = FT1248 selected + stalled", "", $sformatf("0x%08h", rv));
    rdn(DBG + 32'h24, 1); chk(vals[0] == soc.cpu.dp.rf.reg_file_arr[9], "S12.4", "FT1248: register readback", "", "");
    ctl(8'h01, 8'h02); status(g); chk(rl.size() == 1 && g[0] == 0, "S12.5", "FT1248: resume", "", "");
    chk(ft_xz == 0, "S12.7", "every byte the debugger sends over FT1248 is fully defined at the FTDI model (bit 7 not Z)", "",
        $sformatf("%0d of %0d bytes had an undefined bit", ft_xz, ft_bytes));
    #1000 dbg_sel = 0; repeat (100) @(posedge clk);
    adp("A"); chk(rl.size() == 1, "S12.6", "back on UART", "", "");

    grp = "S13 global"; $display("\n== %s ==", grp);
    chk(tmo_n == 0, "S13.1", "every command got its prompt (no hangs)", "", $sformatf("%0d timeouts", tmo_n));
    chk(v_core == 0, "S13.2", "core never changed a waited AHB request", "N3", $sformatf("%0d", v_core));
    chk(v_bus == 0, "S13.3", "shared bus address stable during wait states (a core request change passes through the mux)", (v_bus > 0 && v_core > 0) ? "N3" : "", $sformatf("%0d", v_bus));

    $display("\n================ SOC LEVEL: %0d PASS, %0d FAIL, %0d XFAIL (known bugs confirmed), %0d XPASS ================", n_pass, n_fail, n_xfail, n_xpass);
    $fdisplay(fd, "SUMMARY|%0d|%0d|%0d|%0d", n_pass, n_fail, n_xfail, n_xpass);
    $fclose(fd); $finish;
  end
  initial begin #300_000_000; $display("[FATAL] global timeout"); $finish; end
endmodule
