//-----------------------------------------------------------------------------
// Block-level self-checking verification of the 1TOPS debugger subsystem
//
//  DUT  : riscv_debugger_top (UART + FT1248 + ADP controller)
//         + ahb_mux (fixed) + core_step_controller (WATCHDOG_LIMIT = 64)
//  TB   : host UART BFM, host FT1248 BFM (repo f232h_ft1248_stream device model),
//         ADP reference model (spec = COMMANDS.md, RTL-pinned where the spec is silent),
//         AHB memory slave (random waits, ERROR region, poll counter),
//         random "core" master on M0, fake core retire generator,
//         bus monitors on M0 / M1 / slave side, protocol checkers.
//
//  Verdicts:  PASS  - behaves as specified
//             FAIL  - deviates, not a known issue  (new bug)
//             XFAIL - deviates exactly where a known issue predicts (bug confirmed)
//             XPASS - a known issue did NOT reproduce (bug gone or test wrong)
//  Every check is also written to results_block.txt for the report.
//-----------------------------------------------------------------------------
`timescale 1ns/1ps
module tb_dbg_block;
  localparam integer CLK_FREQ = 100_000_000;
  localparam integer BAUD     = 6_250_000;            // 16 clocks/bit
  localparam integer DEF_UDIV = CLK_FREQ / BAUD;
  localparam integer DEF_FDIV = 2;

  reg clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  // ------------------------------------------------------------ DUT wiring
  reg        dbg_sel = 0;
  reg        uart_rx = 1'b1;
  wire       uart_tx;
  wire       ft_clk, ft_ssn, ft_miso; wire [0:0] ft_miosio;
  wire [0:0] ft_mo, ft_moe;                           // declared before use (Icarus 13+ requires it)
  wire       core_halt, core_reset, core_step, core_step_mode;
  wire [7:0] gpo8;
  wire       stall, step_busy, step_done, step_done_flag; wire [31:0] step_count;
  wire       halted = stall & ~step_busy;
  reg  [3:0] tb_fault = 0; reg tb_trap = 0; reg tb_auto = 0;
  wire       retired;
  reg        ahb_uwe = 0, ahb_fwe = 0; reg [15:0] ahb_uval = 0; reg [7:0] ahb_fval = 0;
  wire [15:0] uart_div_o; wire [7:0] ft_div_o;

  // debugger master (M1)
  wire [31:0] d_HADDR, d_HWDATA, d_HRDATA; wire [2:0] d_HBURST, d_HSIZE; wire [3:0] d_HPROT; wire [1:0] d_HTRANS;
  wire d_HWRITE, d_HMASTLOCK, d_HREADY, d_HRESP;
  // core master (M0)
  wire [31:0] c_HADDR, c_HWDATA, c_HRDATA; wire [2:0] c_HBURST, c_HSIZE; wire [3:0] c_HPROT; wire [1:0] c_HTRANS;
  wire c_HWRITE, c_HMASTLOCK, c_HREADY, c_HRESP;
  // slave bus
  wire [31:0] s_HADDR, s_HWDATA, s_HRDATA; wire [2:0] s_HBURST, s_HSIZE; wire [3:0] s_HPROT; wire [1:0] s_HTRANS;
  wire s_HWRITE, s_HMASTLOCK, s_HREADY, s_HRESP, grant_data;

  riscv_debugger_top #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD), .FT_WIDTH(1), .FT_CLKDIV(DEF_FDIV[7:0])) dut (
    .clk(clk), .rst_n(rst_n), .dbg_sel(dbg_sel), .uart_rx(uart_rx), .uart_tx(uart_tx),
    .ft1248_clk(ft_clk), .ft1248_ss_n(ft_ssn), .ft1248_miso(ft_miso),
    .ft1248_miosio_o(ft_mo), .ft1248_miosio_oe(ft_moe), .ft1248_miosio_i(ft_miosio),
    .core_halt_o(core_halt), .core_reset_o(core_reset), .core_halted_i(halted),
    .core_step_o(core_step), .core_step_mode_o(core_step_mode), .core_step_busy_i(step_busy), .core_step_done_i(step_done),
    .DEBUG_HADDR(d_HADDR), .DEBUG_HBURST(d_HBURST), .DEBUG_HMASTLOCK(d_HMASTLOCK), .DEBUG_HPROT(d_HPROT),
    .DEBUG_HSIZE(d_HSIZE), .DEBUG_HTRANS(d_HTRANS), .DEBUG_HWDATA(d_HWDATA), .DEBUG_HWRITE(d_HWRITE),
    .DEBUG_HRDATA(d_HRDATA), .DEBUG_HREADY(d_HREADY), .DEBUG_HRESP(d_HRESP),
    .GPO8(gpo8), .GPI8({tb_fault, tb_trap, step_done_flag, step_busy, halted}),
    .ahb_uart_clkdiv_we_i(ahb_uwe), .ahb_uart_clkdiv_i(ahb_uval), .ahb_ft_clkdiv_we_i(ahb_fwe), .ahb_ft_clkdiv_i(ahb_fval),
    .uart_clkdiv_o(uart_div_o), .ft_clkdiv_o(ft_div_o));

  core_step_controller #(.WATCHDOG_LIMIT(64)) u_step (
    .clk(clk), .rst_n(rst_n), .halt_req_i(core_halt), .step_req_i(core_step), .step_mode_i(core_step_mode),
    .auto_halt_req_i(tb_auto), .instr_retired_i(retired), .core_stall_ext_i(1'b0),
    .core_stall_o(stall), .step_busy_o(step_busy), .step_done_o(step_done), .step_count_o(step_count), .step_done_flag_o(step_done_flag));

  fake_core u_core (.clk(clk), .rstn(rst_n), .stall(stall), .retired(retired));

  ahb_core_master u_cm (.clk(clk), .rstn(rst_n), .HADDR(c_HADDR), .HTRANS(c_HTRANS), .HWRITE(c_HWRITE), .HSIZE(c_HSIZE),
    .HBURST(c_HBURST), .HPROT(c_HPROT), .HMASTLOCK(c_HMASTLOCK), .HWDATA(c_HWDATA), .HRDATA(c_HRDATA), .HREADY(c_HREADY), .HRESP(c_HRESP));

  ahb_mux #(.ADDR_WIDTH(32), .DATA_WIDTH(32)) u_mux (
    .HCLK(clk), .HRESETn(rst_n),
    .M0_HADDR(c_HADDR), .M0_HWDATA(c_HWDATA), .M0_HWRITE(c_HWRITE), .M0_HTRANS(c_HTRANS), .M0_HSIZE(c_HSIZE), .M0_HBURST(c_HBURST),
    .M0_HPROT(c_HPROT), .M0_HMASTLOCK(c_HMASTLOCK), .M0_HRDATA(c_HRDATA), .M0_HREADY(c_HREADY), .M0_HRESP(c_HRESP),
    .M1_HADDR(d_HADDR), .M1_HWDATA(d_HWDATA), .M1_HWRITE(d_HWRITE), .M1_HTRANS(d_HTRANS), .M1_HSIZE(d_HSIZE), .M1_HBURST(d_HBURST),
    .M1_HPROT(d_HPROT), .M1_HMASTLOCK(d_HMASTLOCK), .M1_HRDATA(d_HRDATA), .M1_HREADY(d_HREADY), .M1_HRESP(d_HRESP),
    .S_HADDR(s_HADDR), .S_HWDATA(s_HWDATA), .S_HWRITE(s_HWRITE), .S_HTRANS(s_HTRANS), .S_HSIZE(s_HSIZE), .S_HBURST(s_HBURST),
    .S_HPROT(s_HPROT), .S_HMASTLOCK(s_HMASTLOCK), .S_HRDATA(s_HRDATA), .S_HREADY(s_HREADY), .S_HRESP(s_HRESP), .grant_data(grant_data));

  ahb_mem_slave slv (.clk(clk), .rstn(rst_n), .HADDR(s_HADDR), .HTRANS(s_HTRANS), .HWRITE(s_HWRITE), .HSIZE(s_HSIZE),
    .HBURST(s_HBURST), .HPROT(s_HPROT), .HWDATA(s_HWDATA), .HRDATA(s_HRDATA), .HREADY(s_HREADY), .HRESP(s_HRESP));

  // ------------------------------------------------------------ FT1248 host
  wire ftb_miso, ftb_mio_o, ftb_mio_z; wire [7:0] ftb_tx_data; wire ftb_tx_valid, ftb_rx_ready;
  reg  ftb_tx_ready = 1'b1; reg [7:0] ftb_rx_data = 0; reg ftb_rx_valid = 0;
  assign ft_miosio[0] = (!ftb_mio_z) ? ftb_mio_o : 1'bz;
  assign ft_miso      = ftb_miso;
  assign ft_miosio[0] = ft_moe[0] ? ft_mo[0] : 1'bz;   // pad, as in riscv_soc_ahb.v
  f232h_ft1248_stream u_ftdev (
    .ft_clk_i(ft_clk), .ft_ssn_i(ft_ssn), .ft_miso_o(ftb_miso), .ft_miosio_i(ft_miosio[0]), .ft_miosio_o(ftb_mio_o), .ft_miosio_z(ftb_mio_z),
    .aclk(clk), .aresetn(rst_n), .txd_tvalid_o(ftb_tx_valid), .txd_tdata8_o(ftb_tx_data), .txd_tready_i(ftb_tx_ready),
    .rxd_tready_o(ftb_rx_ready), .rxd_tdata8_i(ftb_rx_data), .rxd_tvalid_i(ftb_rx_valid));

  // ------------------------------------------------------------ verdicts
  integer n_pass = 0, n_fail = 0, n_xfail = 0, n_xpass = 0, fd;
  string  grp = "";
  task automatic chk(input bit ok, input string id, input string name, input string tag, input string detail);
    string v, t1s, t2s;
    begin
      if (ok && tag == "")       begin v = "PASS";  n_pass++;  end
      else if (ok)               begin v = "XPASS"; n_xpass++; end
      else if (tag == "")        begin v = "FAIL";  n_fail++;  end
      else                       begin v = "XFAIL"; n_xfail++; end
      t1s = ""; t2s = "";
      if (tag != "") t1s = {"  {", tag, "}"};
      if (!ok && detail != "") t2s = {"\n            ", detail};
      $display("  [%-5s] %-7s %s%s%s", v, id, name, t1s, t2s);
      $fdisplay(fd, "%s|%s|%s|%s|%s|%s", grp, id, name, v, tag, detail);
    end
  endtask

  // ------------------------------------------------------------ host side
  integer host_div = DEF_UDIV;           // clocks per bit the host uses
  reg [7:0] uq [$];                      // bytes received on UART
  reg [7:0] fq [$];                      // bytes received on FT1248
  integer uart_frame_err = 0;

  task automatic uart_send(input [7:0] b, input bit bad_stop);
    integer i; real bt;
    begin
      bt = host_div * 10.0;
      uart_rx = 0; #(bt);
      for (i = 0; i < 8; i++) begin uart_rx = b[i]; #(bt); end
      uart_rx = bad_stop ? 1'b0 : 1'b1; #(bt);
      uart_rx = 1; #(bt);
    end
  endtask
  task automatic ft_send(input [7:0] b);
    integer t;
    begin
      @(posedge clk); #1 ftb_rx_data = b; ftb_rx_valid = 1;
      t = 0; @(posedge clk); while (!ftb_rx_ready && t < 200000) begin @(posedge clk); t++; end
      #1 ftb_rx_valid = 0;
      repeat (4) @(posedge clk);
    end
  endtask
  task automatic host_send(input [7:0] b);
    if (dbg_sel) ft_send(b); else uart_send(b, 1'b0);
  endtask
  task automatic host_str(input string s);
    integer i; for (i = 0; i < s.len(); i++) host_send(s[i]);
  endtask

  // UART receiver (host side)
  reg [7:0] urx;
  always begin
    real bt;
    @(negedge uart_tx);
    bt = host_div * 10.0;
    #(bt / 2);
    if (uart_tx === 1'b0) begin
      repeat (8) begin #(bt); urx = {uart_tx, urx[7:1]}; end
      #(bt); if (uart_tx !== 1'b1) uart_frame_err++;
      uq.push_back(urx);
    end
  end
  // FT1248 receiver
  integer ft_xz = 0, ft_bytes = 0;
  always @(posedge clk) if (rst_n && ftb_tx_valid && ftb_tx_ready) begin
    fq.push_back(ftb_tx_data); ft_bytes++; if ((^ftb_tx_data) === 1'bx) ft_xz++;
  end

  function automatic string vis(input string s);
    integer i; string r; reg [7:0] c; r = "";
    for (i = 0; i < s.len(); i++) begin
      c = s[i];
      if (c == 8'h0a) r = {r, "\\n"}; else if (c == 8'h0d) r = {r, "\\r"};
      else if (c < 8'h20 || c > 8'h7e) r = {r, $sformatf("\\x%02x", c)}; else r = {r, string'(c)};
    end
    return r;
  endfunction
  function automatic string chcase(input string s, input bit up);
    integer i; string r; reg [7:0] c; r = "";
    for (i = 0; i < s.len(); i++) begin
      c = s[i];
      if (up && c >= "a" && c <= "z") c = c - 32; else if (!up && c >= "A" && c <= "Z") c = c + 32;
      r = {r, string'(c)};
    end
    return r;
  endfunction
  function automatic bit match(input string got, input string exp);   // '?' in exp = any char
    integer i; bit ok;
    ok = (got.len() == exp.len());
    for (i = 0; ok && i < exp.len(); i++) if (exp[i] != "?" && exp[i] != got[i]) ok = 0;
    return ok;
  endfunction

  // ------------------------------------------------------------ bus monitors
  // record = {resp, write, size[1:0], addr[31:0], data[31:0]}
  reg [67:0] m1_obs [$], m1_all [$], m0_all [$], sd_all [$], sc_all [$];
  reg m1_dv, m0_dv, s_dv; reg m1_dw, m0_dw, s_dw; reg [1:0] m1_ds, m0_ds, s_ds; reg [31:0] m1_da, m0_da, s_da; reg s_dprot;
  integer m1_viol = 0, mix_err = 0, m1_xfers = 0, m1_burst_bad = 0;
  reg m1_wait_p; reg [36:0] m1_req_p; reg m1_wdp_wait_p; reg [31:0] m1_wd_p;
  initial begin m1_dv = 0; m0_dv = 0; s_dv = 0; m1_wait_p = 0; m1_wdp_wait_p = 0; end
  always @(posedge clk) begin
    if (!rst_n) begin m1_dv = 0; m0_dv = 0; s_dv = 0; m1_wait_p = 0; m1_wdp_wait_p = 0; end
    else begin
      // --- debugger master port rules
      if (m1_wait_p && m1_req_p !== {d_HTRANS[1], d_HADDR, d_HWRITE, d_HSIZE[1:0]}) begin m1_viol++; $display("  [M1-RULE] %0t debugger changed a waited request", $time); end
      if (m1_wdp_wait_p && d_HWDATA !== m1_wd_p) begin m1_viol++; $display("  [M1-RULE] %0t debugger HWDATA changed in a waited write data phase", $time); end
      if (d_HTRANS == 2'b01 || d_HTRANS == 2'b11) begin m1_viol++; $display("  [M1-RULE] %0t debugger drove BUSY/SEQ", $time); end
      if (d_HTRANS[1] && ((d_HADDR & ((32'h1 << d_HSIZE) - 1)) != 0 || d_HSIZE > 2)) begin m1_viol++; $display("  [M1-RULE] %0t debugger unaligned/oversize transfer %h size %0d", $time, d_HADDR, d_HSIZE); end
      if ((^d_HTRANS) === 1'bx) begin m1_viol++; $display("  [M1-RULE] %0t X on debugger HTRANS", $time); end
      m1_wait_p = d_HTRANS[1] && !d_HREADY; m1_req_p = {d_HTRANS[1], d_HADDR, d_HWRITE, d_HSIZE[1:0]};
      m1_wdp_wait_p = m1_dv && m1_dw && !d_HREADY; m1_wd_p = d_HWDATA;
      // --- M1 transfers
      if (m1_dv && d_HREADY) begin
        m1_obs.push_back({d_HRESP, m1_dw, m1_ds, m1_da, m1_dw ? d_HWDATA : d_HRDATA});
        m1_all.push_back({d_HRESP, m1_dw, m1_ds, m1_da, m1_dw ? d_HWDATA : d_HRDATA});
        m1_dv = 0;
      end
      if (d_HTRANS[1] && d_HBURST !== 3'b000) m1_burst_bad++;
      if (d_HTRANS[1] && d_HREADY) begin m1_dv = 1; m1_dw = d_HWRITE; m1_ds = d_HSIZE[1:0]; m1_da = d_HADDR; m1_xfers++; end
      // --- M0 transfers
      if (m0_dv && c_HREADY) begin m0_all.push_back({c_HRESP, m0_dw, m0_ds, m0_da, m0_dw ? c_HWDATA : c_HRDATA}); m0_dv = 0; end
      if (c_HTRANS[1] && c_HREADY) begin m0_dv = 1; m0_dw = c_HWRITE; m0_ds = c_HSIZE[1:0]; m0_da = c_HADDR; end
      // --- slave-side transfers, attributed by HPROT[0] (debugger = 1, core TB master = 0)
      if (s_dv && s_HREADY) begin
        if (s_dprot) sd_all.push_back({s_HRESP, s_dw, s_ds, s_da, s_dw ? s_HWDATA : s_HRDATA});
        else         sc_all.push_back({s_HRESP, s_dw, s_ds, s_da, s_dw ? s_HWDATA : s_HRDATA});
        s_dv = 0;
      end
      if (s_HTRANS[1] && s_HREADY) begin s_dv = 1; s_dw = s_HWRITE; s_ds = s_HSIZE[1:0]; s_da = s_HADDR; s_dprot = s_HPROT[0]; end
      // --- in-order compare master side vs slave side (no loss, no duplication, no mixing)
      while (m1_all.size() > 0 && sd_all.size() > 0) begin
        if (m1_all[0] !== sd_all[0]) begin mix_err++; if (mix_err < 6) $display("  [MUX] %0t debugger xfer mismatch master=%h slave=%h", $time, m1_all[0], sd_all[0]); end
        void'(m1_all.pop_front()); void'(sd_all.pop_front());
      end
      while (m0_all.size() > 0 && sc_all.size() > 0) begin
        if (m0_all[0] !== sc_all[0]) begin mix_err++; if (mix_err < 6) $display("  [MUX] %0t core xfer mismatch master=%h slave=%h", $time, m0_all[0], sc_all[0]); end
        void'(m0_all.pop_front()); void'(sc_all.pop_front());
      end
    end
  end
  // AXI-stream rule on the UART->ADP byte channel: data must not change while valid && !ready
  integer axis_viol = 0; reg ax_p; reg [7:0] ax_d;
  always @(posedge clk) if (rst_n) begin
    if (ax_p && dut.uart_adp_rx_data !== ax_d) begin axis_viol++; if (axis_viol < 4) $display("  [AXIS] %0t UART RX byte overwritten before the ADP took it (0x%02h -> 0x%02h)", $time, ax_d, dut.uart_adp_rx_data); end
    ax_p = dut.uart_adp_rx_valid && !dut.uart_adp_rx_ready; ax_d = dut.uart_adp_rx_data;
  end

  // ------------------------------------------------------------ ADP reference model
  reg [31:0] m_addr; reg [7:0] m_gpo; reg [15:0] m_udiv; reg [7:0] m_fdiv;
  reg [31:0] m_val; reg [1:0] m_vsize; reg [31:0] m_mask; reg m_pt; reg [31:0] m_poll;
  reg exp_halted, exp_done; string exp_out; reg [66:0] exp_x [$]; reg [7:0] upl [$];
  integer next_host_div;

  task automatic model_reset();
    m_addr = 0; m_gpo = 0; m_udiv = DEF_UDIV; m_fdiv = DEF_FDIV; m_val = 0; m_vsize = 2; m_mask = 0; m_pt = 0; exp_halted = 0; exp_done = 0;
  endtask
  function automatic string hx(input [31:0] v, input [1:0] sz);
    if (sz == 0) return $sformatf("%02x", v[7:0]); else if (sz == 1) return $sformatf("%04x", v[15:0]); else return $sformatf("%08x", v);
  endfunction
  function automatic [31:0] ha_of(input [31:0] a, input [1:0] sz);
    ha_of = (sz == 2) ? {a[31:2], 2'b00} : (sz == 1) ? {a[31:1], 1'b0} : a;
  endfunction
  function automatic [31:0] wd_of(input [31:0] v, input [1:0] sz);
    wd_of = (sz == 2) ? v : (sz == 1) ? {2{v[15:0]}} : {4{v[7:0]}};
  endfunction
  function automatic [1:0] size_of(input integer nd);
    size_of = (nd == 0) ? 2'd2 : (nd <= 2) ? 2'd0 : (nd <= 4) ? 2'd1 : 2'd2;
  endfunction
  function automatic [31:0] peek(input [31:0] a);
    peek = slv.mem[{a[31:28], a[13:2]}];
  endfunction
  task automatic m_rd(input [1:0] sz, input bit inc, output [31:0] shown, output [31:0] raw, output bit err);
    reg [31:0] ha;
    begin
      ha = ha_of(m_addr, sz); exp_x.push_back({1'b0, sz, ha, 32'h0});
      err = (ha[31:28] == 4'hE);
      if (err) raw = 0; else if (ha[31:28] == 4'hC) begin raw = m_poll; m_poll = m_poll + 1; end else raw = peek(ha);
      shown = raw >> (8 * ha[1:0]);
      if (inc) m_addr = m_addr + (32'h1 << sz);
    end
  endtask
  task automatic m_wr(input [31:0] v, input [1:0] sz, output bit err);
    reg [31:0] ha;
    begin
      ha = ha_of(m_addr, sz); exp_x.push_back({1'b1, sz, ha, wd_of(v, sz)});
      err = (ha[31:28] == 4'hE);
      if (ha[31:28] == 4'hC) m_poll = wd_of(v, sz);
      m_addr = m_addr + (32'h1 << sz);
    end
  endtask
  function automatic bit ishex(input [7:0] c);
    return (c >= "0" && c <= "9") || (c >= "a" && c <= "f") || (c >= "A" && c <= "F");
  endfunction
  function automatic [3:0] hexv(input [7:0] c);
    return (c >= "0" && c <= "9") ? c - "0" : (c >= "a" && c <= "f") ? c - "a" + 10 : c - "A" + 10;
  endfunction

  // predict(): expected output text + expected debugger bus transfers for one command line
  task automatic predict(input string line);
    integer i, nd, n, k, found; reg [15:0] old_udiv; reg [7:0] c, up; reg [31:0] v, shown, raw; reg [1:0] sz; bit e, err, ex, blank;
    begin
      exp_out = ""; exp_x.delete(); m_poll = slv.poll_cnt; next_host_div = host_div;
      i = 0; ex = 0; blank = 0;
      while (i < line.len() && (line[i] == " " || line[i] == 8'h09)) i++;
      if (i >= line.len()) blank = 1;
      else begin
        c = line[i]; i++; if (c == 8'h04) ex = 1;
        v = 0; nd = 0;
        for (; i < line.len(); i++) begin
          if (line[i] == 8'h04) ex = 1;
          else if (line[i] == " " || line[i] == 8'h09 || line[i] == "x" || line[i] == "X") begin v = 0; nd = 0; end
          else if (ishex(line[i])) begin v = {v[27:0], hexv(line[i])}; nd++; end
        end
      end
      sz = size_of(nd);
      up = (c >= "a" && c <= "z") ? c - 8'd32 : c;
      if (blank)   exp_out = "\n\015]";
      else if (ex) begin exp_out = ""; m_pt = 1; end
      else case (up)
        "A": begin if (nd) begin m_addr = v; exp_out = {"A 0x", hx(v, sz)}; end else exp_out = {"A 0x", hx(m_addr, 2)}; exp_out = {exp_out, "\n\015]"}; end
        "R": begin
               n = nd ? v : 0; if (n == 0) n = 1;
               for (k = 0; k < n; k++) begin m_rd(sz, 1, shown, raw, e); exp_out = {exp_out, "R", e ? "!" : " ", "0x", hx(shown, sz), "\n\015"}; end
               exp_out = {exp_out, "]"};
             end
        "W": begin m_wr(v, sz, e); exp_out = {"W", e ? "!" : " ", "0x", hx(v, sz), "\n\015]"}; end
        "C": begin
               if (nd) begin
                 if (v[31:8] == 1) m_gpo = m_gpo & ~v[7:0]; else if (v[31:8] == 2) m_gpo = m_gpo | v[7:0]; else if (v[31:8] == 3) m_gpo = v[7:0];
                 exp_out = {"C 0x??", hx(m_gpo, 0), hx(v, 1), "\n\015]"};                      // spec: always {GPI,GPO,param16}
               end else exp_out = {"C 0x", hx({tb_fault, tb_trap, exp_done, 1'b0, exp_halted}, 0), hx(m_gpo, 0), "0000\n\015]"};
             end
        "B": begin
               old_udiv = m_udiv;
               if (nd) begin
                 if (nd >= 7 && v[31:24] == 8'h03) begin m_udiv = v[23:8]; m_fdiv = v[7:0]; end
                 else if (nd >= 7 && v[31:24] == 8'h02) m_fdiv = v[7:0];
                 else if (nd >= 7 && v[31:24] == 8'h01) m_udiv = v[15:0];
                 else if (nd >= 5 && v[23:16] == 8'h02) m_fdiv = v[7:0];               // spec "B 02<hex8>" e.g. B 020008
                 else m_udiv = v[15:0];                                               // "B <hex16>" and "B 01<hex16>"
                 if (m_udiv < 4) m_udiv = old_udiv;                                  // fixed RTL: < 4 is refused
                 next_host_div = m_udiv;
               end
               exp_out = {"B 0x00", hx(m_fdiv, 0), hx(m_udiv, 1), "\n\015]"};
             end
        "D": begin if (nd) m_fdiv = v[7:0]; exp_out = {"D 0x", hx(m_fdiv, 0), "\n\015]"}; end
        "V": begin if (nd) begin m_val = v; m_vsize = sz; exp_out = {"V 0x", hx(v, sz)}; end else exp_out = {"V 0x", hx(m_val, 2)}; exp_out = {exp_out, "\n\015]"}; end
        "M": begin if (nd) begin m_mask = v; exp_out = {"M 0x", hx(v, sz)}; end else exp_out = {"M 0x", hx(m_mask, 2)}; exp_out = {exp_out, "\n\015]"}; end
        "F": begin
               // spec: "fills <count> words with the pattern set by V"
               n = nd ? v : 0; err = 0;
               for (k = 0; k < n; k++) begin m_wr(m_val, 2'd2, e); err = err | e; end
               exp_out = {"F", err ? "!" : " ", "0x", hx(n, (n >= 1) ? 2'd2 : sz), "\n\015]"};
             end
        "U": begin
               n = nd ? v : 0; err = 0;
               for (k = 0; k < n; k++) begin m_wr({24'h0, upl[k]}, 0, e); err = err | e; end
               exp_out = {"U", err ? "!" : " ", "0x", hx(n, (n >= 1) ? 2'd2 : sz), "\n\015]"};
             end
        "P": begin
               n = nd ? v : 0; err = 0; found = 0;
               for (k = 1; k <= n && !found; k++) begin
                 m_rd(2'd2, 0, shown, raw, e); err = err | e;
                 if ((raw & m_mask) == m_val) found = k;
               end
               if (found) exp_out = {"P", err ? "!" : " ", "0x", hx(found, 2'd2), "\n\015]"};
               else if (n == 0) exp_out = {"P 0x", hx(0, sz), "\n\015]"};
               else       exp_out = {"P!0x", hx(n, 2'd2), "\n\015]"};
             end
        "S": exp_out = {"S 0x", hx(v, sz), "\n\015]"};
        "X": begin exp_out = "\n"; m_pt = 1; end
        default: exp_out = "?\n\015]";
      endcase
    end
  endtask

  // ------------------------------------------------------------ command runner
  string got;
  task automatic collect(input integer exp_len, input integer tmo_ns);
    integer t, last, qn; real quiet; reg [7:0] cb;
    begin
      quiet = dbg_sel ? 20000.0 : host_div * 10.0 * 40;
      t = 0;
      while (((dbg_sel ? fq.size() : uq.size()) < exp_len) && t < tmo_ns) begin #100; t += 100; end
      last = -1;
      while ((dbg_sel ? fq.size() : uq.size()) != last) begin last = dbg_sel ? fq.size() : uq.size(); #(quiet); end
      got = "";
      if (dbg_sel) while (fq.size() > 0) begin cb = fq.pop_front(); got = {got, string'(cb)}; end
      else         while (uq.size() > 0) begin cb = uq.pop_front(); got = {got, string'(cb)}; end
    end
  endtask
  function automatic string xstr(input [67:0] r);
    string a, b; a = "R"; b = "";
    if (r[66]) a = "W"; if (r[67]) b = "!";
    return {a, b, $sformatf("@%08h sz%0d %08h", r[63:32], r[65:64], r[31:0])};
  endfunction
  // compare observed debugger transfers with the model's list (write data compared for writes)
  bit bus_ok_r; string bus_why;
  task automatic bus_ok();
    integer i; reg [67:0] o, ee; reg [66:0] e; bit ok; string why, s1x, s2x;
    ok = (m1_obs.size() == exp_x.size()); why = "";
    if (!ok) why = $sformatf("bus: %0d transfers, expected %0d", m1_obs.size(), exp_x.size());
    for (i = 0; ok && i < exp_x.size(); i++) begin
      o = m1_obs[i]; e = exp_x[i];
      if (o[66] !== e[66] || o[65:64] !== e[65:64] || o[63:32] !== e[63:32] || (e[66] && o[31:0] !== e[31:0])) begin
        ee = {1'b0, e}; ok = 0; s1x = xstr(o); s2x = xstr(ee); why = {"bus #", $sformatf("%0d", i), ": got ", s1x, ", expected ", s2x};
      end
    end
    bus_ok_r = ok; bus_why = why;
  endtask

  // run one command line (terminator added unless term == "")
  task automatic docmd(input string id, input string line, input string term, input string name, input string tag);
    integer k, tmo; string why, d1, d2, vl; bit ok, bok;
    begin
      predict(line);
      m1_obs.delete(); uq.delete(); fq.delete();
      host_str({line, term});
      for (k = 0; k < upl.size(); k++) host_send(upl[k]);
      tmo = 400_000 + exp_x.size() * 2000;
      collect(exp_out.len(), tmo);
      ok = match(got, exp_out); bus_ok(); bok = bus_ok_r; why = bus_why;
      d1 = ""; d2 = "";
      if (!ok) begin d1 = vis(got); d2 = vis(exp_out); d1 = {"reply got '", d1, "' expected '", d2, "'  "}; d2 = ""; end
      if (!bok) d2 = why;
      vl = vis({line, term});
      chk(ok && bok, id, {name, "  [", vl, "]"}, tag, {d1, d2});
      host_div = next_host_div; upl.delete();
    end
  endtask
  // raw bytes, explicit expectation (passthrough tests, resets ...)
  task automatic doraw(input string id, input string bytes, input string exp, input string name, input string tag);
    string v1, v2, v3;
    begin
      m1_obs.delete(); uq.delete(); fq.delete(); exp_x.delete();
      host_str(bytes);
      collect(exp.len(), 300_000);
      v1 = vis(got); v2 = vis(exp); v3 = vis(bytes);
      chk(match(got, exp) && m1_obs.size() == 0, id, {name, "  [", v3, "]"}, tag,
          {"reply got '", v1, "' expected '", v2, "', ", $sformatf("%0d", m1_obs.size()), " bus transfers"});
    end
  endtask

  task automatic do_reset(input string id, input string name);
    begin
      rst_n = 0; uq.delete(); fq.delete(); host_div = DEF_UDIV; model_reset();
      repeat (10) @(posedge clk); #1 rst_n = 1;
      collect(15, 300_000);
      chk(got == " 0x50c1ab04\n\015]", id, name, "", $sformatf("banner got '%s'", vis(got)));
    end
  endtask
  task automatic mem_set(input [31:0] a, input [31:0] d); slv.mem[{a[31:28], a[13:2]}] = d; endtask

  // ------------------------------------------------------------ test sequence
  integer i, j, t0, t1, fc0, fc1, rt0, rt1, sc0, p0, p1, nviol0; reg [31:0] r32; string s, L, v1g, v2g;
  reg [7:0] b8;
  initial begin
    fd = $fopen("results_block.txt", "w");
    model_reset(); slv.max_wait = 0;
    for (i = 0; i < 65536; i++) slv.mem[i] = {i[15:0], ~i[15:0]};
    for (i = 0; i < 1024; i++) slv.mem[{4'h9, i[11:0]}] = 32'h0;          // core window starts at 0 (core shadow)

    // =====================================================================
    grp = "G0 reset"; $display("\n== %s ==", grp);
    repeat (5) @(posedge clk);
    chk(gpo8 === 8'h00 && core_halt === 0 && core_reset === 0 && core_step === 0, "G0.1", "GPO8 / halt / reset / step outputs are 0 during reset", "", "");
    chk(d_HTRANS === 2'b00, "G0.2", "debugger HTRANS is IDLE during reset", "", "");
    chk(uart_tx === 1'b1, "G0.3", "UART TX idles high during reset", "", "");
    do_reset("G0.4", "banner ' 0x50c1ab04\\n\\r]' after reset");
    docmd("G0.5", "B", "\n", "default dividers (UART = CLK/BAUD, FT = FT_CLKDIV)", "");
    chk(uart_div_o == DEF_UDIV && ft_div_o == DEF_FDIV, "G0.6", "uart_clkdiv_o / ft_clkdiv_o ports show the defaults", "", $sformatf("%0d %0d", uart_div_o, ft_div_o));
    // reset in the middle of a reply
    m1_obs.delete(); host_str("R 00000008\n"); #(16 * 10 * 10 * 20);
    do_reset("G0.7", "reset in the middle of a reply -> clean banner again");
    docmd("G0.8", "A", "\n", "address register cleared by reset", "");

    u_cm.enable = 1;                                        // core traffic runs from here on

    // =====================================================================
    grp = "G1 parser"; $display("\n== %s ==", grp);
    docmd("G1.1",  "a 80000010", "\n", "lowercase command", "");
    docmd("G1.2",  "   A 80000020", "\n", "leading spaces", "");
    docmd("G1.3",  {8'h09, "A", 8'h09, "80000030"}, "\n", "tabs as separators", "");
    docmd("G1.4",  "A80000040", "\n", "no space between command and value", "");
    docmd("G1.5",  "A 0x80000050", "\n", "0x prefix", "");
    docmd("G1.6",  "A 0X80000060", "\n", "0X prefix", "");
    docmd("G1.7",  "A 180000070", "\n", "9 digits keep the last 8", "");
    docmd("G1.8",  "A 8000g0080", "\n", "non-hex characters ignored", "");
    docmd("G1.9",  "A 11 80000090", "\n", "second value replaces the first", "");
    docmd("G1.10", "A 800000a0", "\015", "CR terminates a command", "");
    docmd("G1.11", "A 800000b0", "\015\n", "CRLF line ending (terminal default) gives no extra output", "");
    docmd("G1.12", "", "\n", "empty line gives just a new prompt", "");
    docmd("G1.13", "   ", "\n", "line with only spaces gives just a new prompt", "");
    docmd("G1.14", "Z", "\n", "unknown command -> '?'", "");
    docmd("G1.15", "Z 1234", "\n", "unknown command with a value -> '?'", "");
    docmd("G1.16", "q", "\n", "unknown lowercase command -> '?'", "");
    docmd("G1.17", {8'h1b, " 12"}, "\n", "ESC as a command character -> '?'", "");
    docmd("G1.18", "A                                        800000c0", "\n", "very long line (40 spaces)", "");
    docmd("G1.19", "AAAAAAAAAA", "\n", "letters that are hex digits are values (A AAAAAAAAA)", "");
    docmd("G1.20", "A", "\n", "address query after G1.19", "");

    // =====================================================================
    grp = "G2 address"; $display("\n== %s ==", grp);
    docmd("G2.1", "A 8", "\n", "1 digit: echo 2 digits", "");
    docmd("G2.2", "A 12", "\n", "2 digits", "");
    docmd("G2.3", "A 123", "\n", "3 digits: echo 4", "");
    docmd("G2.4", "A 1234", "\n", "4 digits", "");
    docmd("G2.5", "A 12345", "\n", "5 digits: echo 8", "");
    docmd("G2.6", "A 80000100", "\n", "8 digits", "");
    docmd("G2.7", "A", "\n", "query shows the full address", "");
    docmd("G2.8", "A ffffffff", "\n", "all-ones address", "");
    docmd("G2.9", "A 0", "\n", "zero address", "");

    // =====================================================================
    grp = "G3 read"; $display("\n== %s ==", grp);
    mem_set(32'h8000_0200, 32'h4433_2211); mem_set(32'h8000_0204, 32'h8877_6655); mem_set(32'h8000_0208, 32'hccbb_aa99); mem_set(32'h8000_020c, 32'h00ff_eedd);
    docmd("G3.1",  "A 80000200", "\n", "set address", "");
    docmd("G3.2",  "R", "\n", "plain R = one word, address += 4", "");
    docmd("G3.3",  "A", "\n", "address advanced by 4", "");
    docmd("G3.4",  "A 80000200", "\n", "", "");
    docmd("G3.5",  "R 4", "\n", "R 4 = 4 byte reads, one line each", "");
    docmd("G3.6",  "R 0004", "\n", "R 0004 = 4 halfword reads", "");
    docmd("G3.7",  "A 80000200", "\n", "", "");
    docmd("G3.8",  "R 00000004", "\n", "R 00000004 = 4 word reads", "");
    docmd("G3.9",  "A 80000201", "\n", "", "");
    docmd("G3.10", "R 3", "\n", "byte reads at offsets 1,2,3 (lane rotation)", "");
    docmd("G3.11", "A 80000202", "\n", "", "");
    docmd("G3.12", "R 0001", "\n", "halfword at offset 2", "");
    docmd("G3.13", "A 80000201", "\n", "", "");
    docmd("G3.14", "R 0002", "\n", "halfword at odd address (aligned down on the bus)", "");
    docmd("G3.15", "A 80000203", "\n", "", "");
    docmd("G3.16", "R", "\n", "word at unaligned address (aligned down on the bus)", "");
    docmd("G3.17", "A 80000200", "\n", "", "");
    docmd("G3.18", "R 004", "\n", "3-digit count = halfword reads", "");
    docmd("G3.19", "R 0", "\n", "R 0 (one read)", "");
    docmd("G3.20", "R 00000010", "\n", "16-word burst", "");
    docmd("G3.21", "A dffffffc", "\n", "", "");
    docmd("G3.22", "R 00000003", "\n", "reads crossing into an ERROR region: R! on the failing ones", "");
    docmd("G3.23", "A e0000000", "\n", "", "");
    docmd("G3.24", "R", "\n", "single read with ERROR -> 'R!0x...'", "");
    docmd("G3.25", "R 01", "\n", "next read after an error is clean again? (still error region)", "");
    docmd("G3.26", "A 80000200", "\n", "", "");
    docmd("G3.27", "R", "\n", "error flag cleared for the next command", "");

    // =====================================================================
    grp = "G4 write"; $display("\n== %s ==", grp);
    mem_set(32'h8000_0300, 32'h0000_0000); mem_set(32'h8000_0304, 32'h0000_0000);
    docmd("G4.1",  "A 80000300", "\n", "", "");
    docmd("G4.2",  "W 11223344", "\n", "word write, address += 4", "");
    docmd("G4.3",  "W aa", "\n", "byte write lane 0", "");
    docmd("G4.4",  "W bb", "\n", "byte write lane 1", "");
    docmd("G4.5",  "W cccc", "\n", "halfword write lanes 2-3", "");
    chk(peek(32'h8000_0300) == 32'h1122_3344 && peek(32'h8000_0304) == 32'hcccc_bbaa, "G4.6", "memory holds exactly the written lanes", "",
        $sformatf("%08h %08h", peek(32'h8000_0300), peek(32'h8000_0304)));
    docmd("G4.7",  "A 80000304", "\n", "", "");
    docmd("G4.8",  "R", "\n", "read back merged word", "");
    docmd("G4.9",  "A e0000010", "\n", "", "");
    docmd("G4.10", "W 12345678", "\n", "write with ERROR -> 'W!0x...'", "");
    docmd("G4.11", "A 80000308", "\n", "", "");
    docmd("G4.12", "W", "\n", "W with no value writes 0", "");
    docmd("G4.13", "A fffffffc", "\n", "", "");
    docmd("G4.14", "W 5555aaaa", "\n", "write at top of the address space", "");
    docmd("G4.15", "W 6666bbbb", "\n", "address wraps to 0x00000000", "");
    docmd("G4.16", "A 80000311", "\n", "", "");
    docmd("G4.17", "W 1234", "\n", "halfword write at odd address (aligned down on the bus)", "");
    docmd("G4.18", "W 0x0000x9", "\n", "'x' inside a value restarts it (byte write of 09)", "");

    // =====================================================================
    grp = "G5 control/status"; $display("\n== %s ==", grp);
    docmd("G5.1",  "C", "\n", "status query = {GPI8, GPO8, 0000}", "");
    docmd("G5.2",  "C 00000201", "\n", "set bit0 (core reset)", "");
    chk(core_reset === 1 && gpo8 == m_gpo, "G5.3", "core_reset_o = 1", "", "");
    docmd("G5.4",  "C 00000101", "\n", "clear bit0", "");
    chk(core_reset === 0 && gpo8 == m_gpo, "G5.5", "core_reset_o = 0", "", "");
    docmd("G5.6",  "C 000003a5", "\n", "overwrite GPO8 = a5", "");
    chk(gpo8 === 8'ha5, "G5.7", "GPO8 port = a5", "", $sformatf("%02h", gpo8));
    docmd("G5.8",  "C 000001ff", "\n", "clear all", "");
    docmd("G5.9",  "C 00000402", "\n", "unknown sub-command changes nothing", "");
    chk(gpo8 === 8'h00, "G5.10", "GPO8 unchanged by unknown sub-command", "", "");
    tb_fault = 4'b1010; tb_trap = 1; #200;
    docmd("G5.11", "C", "\n", "GPI8 inputs reported (fault flags, trap latched)", "");
    tb_fault = 0; tb_trap = 0; #200;
    docmd("G5.12", "C 0202", "\n", "4-digit form (doc example) still reports GPI/GPO", "C11");
    docmd("G5.13", "C 0102", "\n", "4-digit resume (doc example)", "C11");
    docmd("G5.14", "c", "\n", "lowercase status query", "");

    // =====================================================================
    grp = "G6 dividers"; $display("\n== %s ==", grp);
    docmd("G6.1",  "D", "\n", "FT divider query", "");
    docmd("G6.2",  "D 05", "\n", "set FT divider", "");
    chk(ft_div_o == 5, "G6.3", "ft_clkdiv_o = 5", "", "");
    docmd("G6.4",  "D 2", "\n", "restore FT divider (1 digit)", "");
    docmd("G6.5",  "B 0014", "\n", "B <hex16>: UART divider 16 -> 20, reply at old baud", "");
    docmd("G6.6",  "A 80000400", "\n", "next command works at the new baud", "");
    chk(uart_div_o == 20, "G6.7", "uart_clkdiv_o = 20", "", "");
    docmd("G6.8",  "B 010010", "\n", "B 01<hex16> back to 16", "");
    docmd("G6.9",  "B 020007", "\n", "B 02<hex8> sets only the FT divider (doc: B 020008)", "");
    if (uart_div_o != m_udiv) begin do_reset("G6.9r", "recover after G6.9 (UART baud was changed by mistake)"); u_cm.enable = 1; end
    docmd("G6.10", "B 03001002", "\n", "B 03<uart16><ft8> sets both", "");
    docmd("G6.11", "B 0003", "\n", "UART divider < 4 is not applied (baud stays)", "");
    chk(uart_div_o == dut.u_uart.clks_per_bit_reg, "G6.12", "reported UART divider equals the one in use", "",
        $sformatf("register %0d, UART uses %0d", uart_div_o, dut.u_uart.clks_per_bit_reg));
    docmd("G6.13", "B 0010", "\n", "restore 16", "");
    docmd("G6.14", "b", "\n", "lowercase query", "");
    // effective UART bit time
    begin : uart_bit
      real tf, tr;
      fork host_str("A\n"); join_none
      @(negedge uart_tx); tf = $realtime; @(posedge uart_tx); tr = $realtime;
      collect(0, 1000);
      chk((tr - tf) >= 159.0 && (tr - tf) <= 161.0, "G6.15", "UART bit time = divider x clock (16 x 10 ns)", "", $sformatf("%0f ns", tr - tf));
    end
    // effective FT clock period vs divider: 2 x (div + 1) clocks
    begin : ftclk
      real a, b2; integer d;
      for (d = 0; d < 3; d++) begin
        @(posedge clk); #1 force dut.u_socdebug_ahb.u_adp_control.ft_clkdiv_o = d; repeat (40) @(posedge clk);
        @(posedge ft_clk); a = $realtime; @(posedge ft_clk); b2 = $realtime;
        chk((b2 - a) == 20.0 * (d + 1), $sformatf("G6.16.%0d", d), $sformatf("FT1248 clock period = 2 x (div+1) clocks for div=%0d", d), "", $sformatf("%0f ns", b2 - a));
      end
      release dut.u_socdebug_ahb.u_adp_control.ft_clkdiv_o;
      @(posedge clk); #1 ahb_fwe = 1; ahb_fval = DEF_FDIV; @(posedge clk); #1 ahb_fwe = 0;
    end
    // core (AHB) writes the UART divider in the middle of a long reply: the reply must stay intact
    docmd("G6.17", "A 80000200", "\n", "", "");
    begin : corewrite
      predict("R 00000006"); m1_obs.delete(); uq.delete();
      host_str("R 00000006\n");
      #(16 * 10 * 10 * 12);
      @(posedge clk); #1 ahb_uwe = 1; ahb_uval = 16'd24; @(posedge clk); #1 ahb_uwe = 0;
      collect(exp_out.len(), 400_000);
      chk(match(got, exp_out), "G6.18", "core writes UART divider mid-reply: reply finishes at the old baud", "", $sformatf("got '%s'", vis(got)));
      m_udiv = 24; host_div = 24;
      docmd("G6.19", "B", "\n", "core-written divider visible to B, link works at the new baud", "");
      @(posedge clk); #1 ahb_fwe = 1; ahb_fval = 8'd3; @(posedge clk); #1 ahb_fwe = 0; m_fdiv = 3;
      docmd("G6.20", "D", "\n", "core-written FT divider visible to D", "");
      docmd("G6.21", "B 03001002", "\n", "restore both", "");
    end

    // =====================================================================
    grp = "G7 value/mask/fill"; $display("\n== %s ==", grp);
    docmd("G7.1",  "V 12345678", "\n", "set value", "");
    docmd("G7.2",  "V", "\n", "query value", "");
    docmd("G7.3",  "M 0000ffff", "\n", "set mask", "");
    docmd("G7.4",  "M", "\n", "query mask", "");
    docmd("G7.5",  "M 0f", "\n", "2-digit mask echo", "");
    docmd("G7.6",  "A 80000500", "\n", "", "");
    docmd("G7.7",  "F 8", "\n", "fill 8 words", "");
    docmd("G7.8",  "A", "\n", "address advanced by 8 words", "");
    docmd("G7.9",  "A 80000500", "\n", "", "");
    docmd("G7.10", "R 00000008", "\n", "read back the fill", "");
    docmd("G7.11", "F 2", "\n", "fill 2", "");
    docmd("G7.12", "F 1", "\n", "fill 1 word", "");
    docmd("G7.13", "F 0", "\n", "fill 0 = no writes", "");
    docmd("G7.14", "V ab", "\n", "2-digit value", "");
    docmd("G7.15", "A 80000540", "\n", "", "");
    docmd("G7.16", "F 4", "\n", "fill after a byte-sized V (doc says words)", "C11");
    docmd("G7.17", "V cafef00d", "\n", "", "");
    docmd("G7.18", "A 80000580", "\n", "", "");
    docmd("G7.19", "F 00000040", "\n", "fill 64 words with core traffic", "");
    docmd("G7.20", "A dffffff8", "\n", "", "");
    docmd("G7.21", "F 4", "\n", "fill crossing into ERROR region -> F!", "");
    docmd("G7.22", "A dffffff8", "\n", "", "");
    docmd("G7.23", "F 3", "\n", "fill where only the LAST beat errors -> F!", "");
    docmd("G7.24", "A 80000500", "\n", "", "");

    // =====================================================================
    grp = "G8 upload"; $display("\n== %s ==", grp);
    docmd("G8.1",  "A 80000600", "\n", "", "");
    upl = '{8'h00, 8'h0a, 8'h0d, 8'h04, 8'h1b, 8'hff, 8'h20, 8'h5d};
    docmd("G8.2",  "U 8", "\n", "upload 8 binary bytes incl. 00 0a 0d 04 1b ff (binary safe)", "");
    chk(peek(32'h8000_0600) == 32'h040d_0a00 && peek(32'h8000_0604) == 32'h5d20_ff1b, "G8.3", "uploaded bytes landed little-endian", "",
        $sformatf("%08h %08h", peek(32'h8000_0600), peek(32'h8000_0604)));
    docmd("G8.4",  "A", "\n", "address advanced by 8", "");
    for (i = 0; i < 64; i++) begin b8 = i * 7; upl.push_back(b8); end
    docmd("G8.5",  "U 40", "\n", "upload 64 bytes with core traffic", "");
    upl = '{8'h77, 8'h88};
    docmd("G8.6",  "U 2", "\n", "upload 2 bytes", "");
    upl = '{8'h20};
    docmd("G8.7",  "U 1", "\n", "upload 1 byte", "");
    collect(0, 20000);
    docmd("G8.8",  "U 0", "\n", "upload 0 bytes", "");
    docmd("G8.9",  "A dffffffe", "\n", "", "");
    upl = '{8'h01, 8'h02, 8'h03, 8'h04};
    docmd("G8.10", "U 4", "\n", "upload crossing into ERROR region -> U!", "");
    docmd("G8.11", "A dffffffe", "\n", "", "");
    upl = '{8'h01, 8'h02, 8'h03};
    docmd("G8.12", "U 3", "\n", "upload where only the LAST byte errors -> U!", "");

    // =====================================================================
    grp = "G9 poll"; $display("\n== %s ==", grp);
    slv.poll_cnt = 0;
    docmd("G9.1",  "A c0000000", "\n", "poll counter register (read returns n, n+1, ...)", "");
    docmd("G9.2",  "W 00000000", "\n", "counter = 0", "");
    docmd("G9.3",  "A c0000000", "\n", "", "");
    docmd("G9.4",  "M ffffffff", "\n", "", "");
    docmd("G9.5",  "V 00000000", "\n", "", "");
    docmd("G9.6",  "P 00000010", "\n", "match on the first read -> P 0x1", "");
    docmd("G9.7",  "A", "\n", "P does not move the address", "");
    docmd("G9.8",  "W 00000000", "\n", "", "");  docmd("G9.8a", "A c0000000", "\n", "", "");
    docmd("G9.9",  "V 00000005", "\n", "", "");
    docmd("G9.10", "P 00000010", "\n", "match on the 6th read -> P 0x6", "");
    docmd("G9.11", "W 00000000", "\n", "", "");  docmd("G9.11a", "A c0000000", "\n", "", "");
    docmd("G9.12", "V 00000003", "\n", "", "");
    docmd("G9.13", "P 00000005", "\n", "match on read t-1 (4th of 5) must still count", "");
    docmd("G9.14", "W 00000000", "\n", "", "");  docmd("G9.14a", "A c0000000", "\n", "", "");
    docmd("G9.15", "V 00000100", "\n", "never matches", "");
    docmd("G9.16", "P 00000005", "\n", "timeout after t reads -> P!", "");
    docmd("G9.17", "W 00000000", "\n", "", "");  docmd("G9.17a", "A c0000000", "\n", "", "");
    docmd("G9.18", "V 00000000", "\n", "", "");
    docmd("G9.19", "P 00000002", "\n", "P 2 with immediate match", "");
    docmd("G9.20", "P 00000001", "\n", "P 1 polls once", "");
    docmd("G9.21", "W 00000000", "\n", "", "");  docmd("G9.21a", "A c0000000", "\n", "", "");
    docmd("G9.22", "M 00000002", "\n", "mask: only bit 1", "");
    docmd("G9.23", "V 00000002", "\n", "", "");
    docmd("G9.24", "P 00000010", "\n", "masked compare matches at counter=2 -> P 0x3", "");
    docmd("G9.25", "W 00000000", "\n", "", "");  docmd("G9.25a", "A c0000000", "\n", "", "");
    docmd("G9.26", "P 40", "\n", "2-digit timeout: poll reads must still be word reads", "");
    docmd("G9.27", "A e0000000", "\n", "", "");
    docmd("G9.28", "M ffffffff", "\n", "", "");  docmd("G9.29", "V 00000000", "\n", "", "");
    docmd("G9.30", "P 00000010", "\n", "poll an ERROR address -> P!", "");

    // =====================================================================
    grp = "G10 stdin"; $display("\n== %s ==", grp);
    docmd("G10.1", "S 41", "\n", "S <hex8> reply", "");
    docmd("G10.2", "S", "\n", "S without value", "");

    // =====================================================================
    grp = "G11 exit/passthrough"; $display("\n== %s ==", grp);
    docmd("G11.1", "X", "\n", "X prints a newline and leaves command mode", "");
    doraw("G11.2", "R\nA 1\n", "", "commands ignored in passthrough (no output, no bus)", "");
    doraw("G11.3", {8'h1b}, "\n\015]", "ESC re-enters command mode", "");
    m_pt = 0;
    docmd("G11.4", "A 80000700", "\n", "commands work again", "");
    doraw("G11.5", {"A 12", 8'h04}, "", "Ctrl-D in a value exits silently", "");
    doraw("G11.6", {8'h1b}, "\n\015]", "ESC back", "");
    doraw("G11.7", {8'h04}, "", "Ctrl-D as first character exits silently", "");
    doraw("G11.8", {8'h1b}, "\n\015]", "ESC back", "");
    docmd("G11.9", "A", "\n", "address untouched by the aborted 'A 12'", "");

    // =====================================================================
    grp = "G12 interfaces"; $display("\n== %s ==", grp);
    collect(0, 5000);
    @(posedge clk); #1 dbg_sel = 1; repeat (50) @(posedge clk);
    begin : ftsess
      integer ut;
      ut = 0;
      fork begin repeat (2000) begin @(uart_tx); ut++; end end join_none
      docmd("G12.1", "A 80000800", "\n", "FT1248: set address", "");
      docmd("G12.2", "W 0badf00d", "\n", "FT1248: write", "");
      docmd("G12.3", "A 80000800", "\n", "", "");
      docmd("G12.4", "R", "\n", "FT1248: read back", "");
      docmd("G12.5", "C", "\n", "FT1248: status", "");
      docmd("G12.6", "B", "\n", "FT1248: dividers", "");
      upl = '{8'h0a, 8'h0d, 8'h1b, 8'h04};
      docmd("G12.7", "U 4", "\n", "FT1248: binary upload", "");
      docmd("G12.8", "D 01", "\n", "FT1248: fast FT clock (div 1 = 25 MHz, FT232H max is 30 MHz)", "");
      docmd("G12.9", "R 00000004", "\n", "FT1248: works at div 1", "");
      docmd("G12.10", "D 07", "\n", "FT1248: slow FT clock (div 7)", "");
      docmd("G12.11", "R 00000002", "\n", "FT1248: works at div 7", "");
      docmd("G12.12", "D 02", "\n", "", "");
      chk(ut == 0, "G12.13", "UART TX stays idle while FT1248 is selected", "", $sformatf("%0d edges", ut));
`ifndef VERILATOR
      chk(ft_xz == 0, "G12.13b", "every byte sent over FT1248 is fully defined at the FTDI model (bit 7 not Z)", "", $sformatf("%0d of %0d bytes had an undefined bit", ft_xz, ft_bytes));
`else
      $display("  [INFO ] G12.13b FT1248 bit-7 Z check needs a 4-state simulator (Verilator is 2-state) - see the Icarus run");
`endif
      // bytes typed on the UART while FT is selected must not leak into the debugger
      begin : leak
        integer k2; dbg_sel = 1;
        uart_send("Z", 0); uart_send("\n", 0);
      end
      docmd("G12.14", "A", "\n", "FT session unaffected by UART input", "");
    end
    collect(0, 5000);
    @(posedge clk); #1 dbg_sel = 0;
    m1_obs.delete(); uq.delete(); collect(0, 200_000);
    chk(got == "" && m1_obs.size() == 0, "G12.15", "switching back to UART: nothing typed on the UART earlier is executed", "", $sformatf("spurious output '%s'", vis(got)));
    docmd("G12.16", "A", "\n", "UART works again", "");

    // =====================================================================
    grp = "G13 halt/step"; $display("\n== %s ==", grp);
    u_core.period = 3;
    docmd("G13.1", "C 00000202", "\n", "halt", "");
    repeat (10) @(posedge clk); exp_halted = 1;
    chk(stall === 1 && core_halt === 1, "G13.2", "core_halt_o = 1 and ExternalStall = 1", "", "");
    fc0 = u_core.free_cycles; rt0 = u_core.retire_total; repeat (300) @(posedge clk);
    chk(u_core.free_cycles == fc0 && u_core.retire_total == rt0, "G13.3", "no core progress while halted (300 cycles)", "", "");
    docmd("G13.4", "C", "\n", "status bit0 = halted", "");
    // instruction step
    for (j = 0; j < 4; j++) begin
      rt0 = u_core.retire_total; sc0 = step_count;
      docmd($sformatf("G13.5.%0d", j), "C 00000204", "\n", "instruction step", "");
      repeat (20) @(posedge clk);
      chk(u_core.retire_total == rt0 + 1 && step_count == sc0 + 1 && stall === 1, $sformatf("G13.6.%0d", j), "exactly one instruction retired, core frozen again", "",
          $sformatf("retired %0d, step_count +%0d, stall %b", u_core.retire_total - rt0, step_count - sc0, stall));
      docmd($sformatf("G13.7.%0d", j), "C 00000104", "\n", "clear step bit", "");
    end
    // step bit held high: only one step
    rt0 = u_core.retire_total;
    docmd("G13.8", "C 00000204", "\n", "", "");
    repeat (500) @(posedge clk);
    chk(u_core.retire_total == rt0 + 1, "G13.9", "step bit held high -> still only one step (edge triggered)", "", $sformatf("%0d", u_core.retire_total - rt0));
    exp_done = 1; docmd("G13.10", "C", "\n", "status after step: step_done visible to the host", ""); exp_done = 0;
    docmd("G13.11", "C 00000104", "\n", "", "");
    // cycle step
    docmd("G13.12", "C 00000208", "\n", "step mode = cycle", "");
    for (j = 0; j < 3; j++) begin
      fc0 = u_core.free_cycles;
      docmd($sformatf("G13.13.%0d", j), "C 00000204", "\n", "cycle step", "");
      repeat (20) @(posedge clk);
      chk(u_core.free_cycles == fc0 + 1, $sformatf("G13.14.%0d", j), "cycle step releases the core for exactly 1 clock", "", $sformatf("%0d clocks", u_core.free_cycles - fc0));
      docmd($sformatf("G13.15.%0d", j), "C 00000104", "\n", "", "");
    end
    docmd("G13.16", "C 00000108", "\n", "back to instruction mode", "");
    // watchdog: core never retires
    u_core.period = 0; u_core.pend = 0; fc0 = u_core.free_cycles; sc0 = step_count;
    docmd("G13.17", "C 00000204", "\n", "step with a core that never retires", "");
    repeat (200) @(posedge clk);
    chk(stall === 1 && step_count == sc0 + 1 && (u_core.free_cycles - fc0) >= 63 && (u_core.free_cycles - fc0) <= 65, "G13.18", "watchdog ends the step after WATCHDOG_LIMIT (64) cycles", "",
        $sformatf("ran %0d cycles", u_core.free_cycles - fc0));
    docmd("G13.19", "C 00000104", "\n", "", "");
    u_core.period = 3;
    // resume
    docmd("G13.20", "C 00000102", "\n", "resume", ""); exp_halted = 0;
    fc0 = u_core.free_cycles; repeat (100) @(posedge clk);
    chk(u_core.free_cycles - fc0 >= 99 && u_core.free_cycles - fc0 <= 101 && stall === 0, "G13.21", "core runs after resume", "", "");
    // step request while running is ignored
    rt0 = u_core.retire_total;
    docmd("G13.22", "C 00000204", "\n", "step request while running", "");
    chk(u_step.state == 0 && stall === 0, "G13.23", "step while running is ignored (stays RUN)", "", "");
    docmd("G13.24", "C 00000202", "\n", "halt with the step bit already high", ""); exp_halted = 1;
    rt0 = u_core.retire_total; repeat (200) @(posedge clk);
    chk(u_core.retire_total == rt0, "G13.25", "halting with step bit high does not cause a step", "", "");
    docmd("G13.26", "C 00000106", "\n", "clear step + resume", ""); exp_halted = 0;
    // auto-halt input (trap)
    #1 tb_auto = 1; repeat (5) @(posedge clk);
    chk(stall === 1, "G13.27", "auto-halt request freezes the core with halt bit = 0", "", "");
    exp_halted = 1;
    docmd("G13.28", "C", "\n", "status shows halted on auto-halt", "");
    #1 tb_auto = 0; repeat (5) @(posedge clk); exp_halted = 0;
    chk(stall === 0, "G13.29", "core runs again when auto-halt drops", "", "");

    // =====================================================================
    grp = "G14 step controller unit"; $display("\n== %s ==", grp);
    // direct drive of the shared step controller inputs through force (no UART)
    begin : unit
      force u_step.halt_req_i = 0; force u_step.step_req_i = 0; force u_step.step_mode_i = 0; force u_step.auto_halt_req_i = 0;
      u_core.period = 0;
      force u_step.instr_retired_i = 0;
      @(posedge clk); #1 force u_step.halt_req_i = 1; @(posedge clk); @(posedge clk); #1;
      chk(u_step.state == 1 && stall, "G14.1", "RUN -> HALTED one clock after halt", "", "");
      force u_step.step_req_i = 1; @(posedge clk); #1;
      chk(u_step.state == 2 && !stall && step_busy, "G14.2", "HALTED -> STEPPING on step edge, stall released, busy", "", "");
      force u_step.instr_retired_i = 1; @(posedge clk); #1 force u_step.instr_retired_i = 0;
      chk(u_step.state == 3 && stall && step_done && !step_busy, "G14.3", "retire -> DONE, stall back on, done pulse", "", "");
      @(posedge clk); #1;
      chk(u_step.state == 1 && !step_done, "G14.4", "DONE -> HALTED next clock", "", "");
      force u_step.step_req_i = 0; @(posedge clk); #1 force u_step.step_req_i = 1; @(posedge clk); #1;
      chk(u_step.state == 2, "G14.5", "second step edge starts a new step", "", "");
      force u_step.halt_req_i = 0; @(posedge clk); #1;
      chk(u_step.state == 0 && !stall, "G14.6", "releasing halt during a step returns to RUN", "", "");
      force u_step.step_req_i = 0; force u_step.halt_req_i = 1; @(posedge clk); @(posedge clk); #1;
      force u_step.step_mode_i = 1; force u_step.step_req_i = 1; @(posedge clk); #1;
      chk(u_step.state == 2 && !stall, "G14.7", "cycle step: STEPPING for one clock", "", "");
      @(posedge clk); #1;
      chk(u_step.state == 3 && stall, "G14.8", "cycle step: DONE on the next clock", "", "");
      force u_step.step_req_i = 0; force u_step.step_mode_i = 0; @(posedge clk); @(posedge clk);
      force u_step.halt_req_i = 0; force u_step.auto_halt_req_i = 1; @(posedge clk); @(posedge clk); #1;
      chk(u_step.state == 1, "G14.9", "auto-halt alone halts", "", "");
      force u_step.step_req_i = 1; @(posedge clk); #1;
      chk(u_step.state == 2, "G14.10", "stepping works under auto-halt", "", "");
      force u_step.instr_retired_i = 1; @(posedge clk); #1 force u_step.instr_retired_i = 0; @(posedge clk); #1;
      chk(u_step.state == 1, "G14.11", "back to HALTED under auto-halt", "", "");
      force u_step.step_req_i = 0; force u_step.auto_halt_req_i = 0; @(posedge clk); #1;
      chk(u_step.state == 0, "G14.12", "auto-halt released -> RUN", "", "");
      // reset in the middle of a step
      force u_step.halt_req_i = 1; @(posedge clk); @(posedge clk); #1 force u_step.step_req_i = 1; @(posedge clk); #1;
      chk(u_step.state == 2, "G14.13a", "in STEPPING before reset", "", "");
      release u_step.halt_req_i; release u_step.step_req_i; release u_step.step_mode_i; release u_step.auto_halt_req_i; release u_step.instr_retired_i;
      #1 rst_n = 0; #1;
      chk(u_step.state == 0 && step_count == 0 && stall === 0, "G14.13", "async reset in STEPPING -> RUN, step counter cleared, core free", "", "");
      u_core.period = 3;
      do_reset("G14.14", "system reset recovers the debugger (banner)");
      docmd("G14.15", "C", "\n", "debugger state consistent after reset", "");
    end

    // =====================================================================
    grp = "G15 contention + wait states"; $display("\n== %s ==", grp);
    u_cm.busy_pct = 100;
    for (j = 0; j < 4; j++) begin
      slv.max_wait = (j == 0) ? 0 : (j == 1) ? 1 : (j == 2) ? 3 : 7;
      docmd($sformatf("G15.%0d.1", j), "A 80000900", "\n", $sformatf("wait<=%0d", slv.max_wait), "");
      docmd($sformatf("G15.%0d.2", j), "V 5a5a0000", "\n", "", "");
      docmd($sformatf("G15.%0d.3", j), "F 00000020", "\n", "fill 32 words vs 100% core traffic", "");
      docmd($sformatf("G15.%0d.4", j), "A 80000900", "\n", "", "");
      docmd($sformatf("G15.%0d.5", j), "R 00000020", "\n", "read 32 words back", "");
      upl.delete(); for (i = 0; i < 16; i++) begin b8 = $urandom; upl.push_back(b8); end
      docmd($sformatf("G15.%0d.6", j), "U 10", "\n", "upload 16 bytes", "");
      docmd($sformatf("G15.%0d.7", j), "A 80000900", "\n", "", "");
      docmd($sformatf("G15.%0d.8", j), "R 10", "\n", "16 byte reads", "");
    end
    u_cm.busy_pct = 70; slv.max_wait = 2;

    // =====================================================================
    grp = "G16 robustness"; $display("\n== %s ==", grp);
    // glitch on RX shorter than half a bit is ignored
    m1_obs.delete(); uq.delete(); uart_rx = 0; #(30); uart_rx = 1; collect(0, 50_000);
    chk(got == "" && m1_obs.size() == 0, "G16.1", "RX glitch (3 clocks) is rejected", "", vis(got));
    docmd("G16.2", "A", "\n", "link fine after glitch", "");
    // byte with a bad stop bit
    m1_obs.delete(); uq.delete(); uart_send("Z", 1); collect(0, 50_000);
    docmd("G16.3", "A", "\n", "a framing-error byte ('Z' with stop bit 0) is dropped, next command clean", "");
    // type-ahead: second command sent while the first reply is still going out
    nviol0 = axis_viol;
    predict("A 80000a00"); s = exp_out; predict("A"); s = {s, exp_out};
    m1_obs.delete(); uq.delete(); host_str("A 80000a00\nA\n"); collect(s.len(), 300_000);
    v1g = vis(got); v2g = vis(s);
    chk(got == s, "G16.4", "two commands sent back-to-back (no wait for the prompt) are both executed", "", {"got '", v1g, "' expected '", v2g, "'"});
    chk(axis_viol == nviol0, "G16.5", "UART RX byte is never overwritten before the ADP takes it (AXI-stream rule)", "", $sformatf("%0d overwrites", axis_viol - nviol0));
    collect(0, 100_000); uq.delete();
    predict("A 80000a40"); s = exp_out; predict("A"); s = {s, exp_out}; predict("a"); s = {s, exp_out};
    m1_obs.delete(); uq.delete(); host_str("A 80000a40\nA\na\n"); collect(s.len(), 400_000);
    v1g = vis(got); v2g = vis(s);
    chk(got == s, "G16.4b", "three commands typed back-to-back all run (bytes wait in the RX FIFO)", "", {"got '", v1g, "' expected '", v2g, "'"});
    collect(0, 100_000); uq.delete();
    docmd("G16.6", "A 80000a00", "\n", "resync", "");
    // upload interrupted: debugger waits for all bytes (no timeout) - bytes of a later command become data
    m1_obs.delete(); uq.delete(); host_str("U 4\n"); host_send(8'h11); host_send(8'h22);
    #(200_000);
    host_str("A\n");                                       // 'A' '\n' complete the 4 bytes
    upl = '{8'h11, 8'h22, "A", 8'h0a}; predict("U 4"); collect(exp_out.len(), 300_000);
    chk(match(got, exp_out), "G16.7", "upload waits for all bytes; nothing else is executed meanwhile (pinned behaviour)", "", $sformatf("got '%s'", vis(got)));
    upl.delete();
    docmd("G16.8", "A", "\n", "link fine after the interrupted upload", "");

    // =====================================================================
    grp = "G17 random fuzz"; $display("\n== %s ==", grp);
    slv.max_wait = 3; u_cm.busy_pct = 80;
    for (j = 0; j < 200; j++) begin : fz
      integer kind, nd2; reg [31:0] val, base; string cmdc, ds, cs;
      kind = $urandom_range(10, 0);
      base = ($urandom_range(3, 0) == 0) ? 32'hE000_0000 : 32'h8000_0000; base = base | ($urandom_range(255, 0) << 4);
      nd2 = $urandom_range(8, 1);
      val = $urandom;
      ds = $sformatf("%08x", val); ds = ds.substr(8 - nd2, 7);
      if ($urandom_range(1, 0)) ds = chcase(ds, 1);
      case (kind)
        0: L = $sformatf("A %08x", base | $urandom_range(15, 0));
        1: begin cs = $sformatf("%08x", $urandom_range(5, 1)); L = {"R ", cs.substr(8 - nd2, 7)}; end
        2: L = "R";
        3: L = {"W ", ds};
        4: L = {"V ", ds};
        5: L = {"M ", ds};
        6: begin
             // F n >= 2 outside the ERROR region only (known C2/C5 corners avoided)
             L = $sformatf("F %0x", $urandom_range(9, 2));
             if (m_addr[31:28] == 4'hE || m_addr[31:28] == 4'hD || m_addr[31:28] == 4'hF) L = "A 80000b00";
             if (m_vsize != 2) L = $sformatf("V %08x", val);
           end
        7: L = "C";
        8: L = {"D ", ds.substr(nd2 > 2 ? nd2 - 2 : 0, nd2 - 1)};
        9: L = {"S ", ds.substr(nd2 > 2 ? nd2 - 2 : 0, nd2 - 1)};
        default: L = $sformatf("A %08x", base);
      endcase
      cmdc = L.substr(0, 0);
      if ($urandom_range(1, 0)) L = {chcase(cmdc, 0), L.substr(1, L.len() - 1)};
      if ($urandom_range(3, 0) == 0) L = {"  ", L};
      docmd($sformatf("G17.%0d", j), L, ($urandom_range(1, 0)) ? "\n" : "\015", "random command", "");
    end
    slv.max_wait = 0; u_cm.busy_pct = 70;

    // =====================================================================
    grp = "G18 global checks"; $display("\n== %s ==", grp);
    u_cm.enable = 0; repeat (200) @(posedge clk);
    chk(u_cm.rd_bad == 0 && u_cm.err_bad == 0, "G18.1", $sformatf("core master: %0d reads checked, %0d writes, %0d expected ERRORs - no data or response errors", u_cm.rd_ok, u_cm.wr_n, u_cm.err_ok), "",
        $sformatf("%0d bad reads, %0d bad responses", u_cm.rd_bad, u_cm.err_bad));
    chk(mix_err == 0 && m1_all.size() == 0 && sd_all.size() == 0 && m0_all.size() == 0 && sc_all.size() == 0, "G18.2",
        $sformatf("mux: every core and debugger transfer reached the slave exactly once, unchanged (%0d debugger xfers)", m1_xfers), "",
        $sformatf("%0d mismatches, leftovers %0d %0d %0d %0d", mix_err, m1_all.size(), sd_all.size(), m0_all.size(), sc_all.size()));
    chk(m1_viol == 0, "G18.3", "debugger master obeys AHB-Lite rules (stable waited request, stable HWDATA, aligned, no BUSY/SEQ)", "", $sformatf("%0d violations", m1_viol));
    chk(u_cm.viol == 0, "G18.4", "mux keeps the core's waited request stable (no core-side rule violations)", "", $sformatf("%0d", u_cm.viol));
    chk(slv.viol == 0, "G18.5", "slave bus obeys AHB-Lite rules (stable in wait states, SINGLE, aligned, no X)", "", $sformatf("%0d violations", slv.viol));
    chk(m1_burst_bad == 0, "G18.7", "debugger drives HBURST = SINGLE on every transfer", "", $sformatf("%0d cycles with another HBURST", m1_burst_bad));
    chk(uart_frame_err == 0, "G18.6", "every byte from the debugger UART had a valid stop bit", "", $sformatf("%0d", uart_frame_err));

    $display("\n================ BLOCK LEVEL: %0d PASS, %0d FAIL, %0d XFAIL (known bugs confirmed), %0d XPASS ================",
             n_pass, n_fail, n_xfail, n_xpass);
    $fdisplay(fd, "SUMMARY|%0d|%0d|%0d|%0d", n_pass, n_fail, n_xfail, n_xpass);
    $fclose(fd);
    $finish;
  end
  initial begin #400_000_000; $display("[FATAL] global timeout"); $fdisplay(fd, "SUMMARY|TIMEOUT"); $finish; end
endmodule
