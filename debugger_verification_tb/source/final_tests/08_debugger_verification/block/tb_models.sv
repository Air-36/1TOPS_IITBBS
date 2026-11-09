//-----------------------------------------------------------------------------
// Testbench models for the block-level debugger verification
//   ahb_mem_slave   : AHB-Lite memory slave, random wait states, ERROR region,
//                     auto-increment "poll counter" region, protocol checks
//   ahb_core_master : random AHB-Lite master standing in for the RISC-V core
//                     (Master 0). Self-checking against its own shadow memory.
//   fake_core       : retire-pulse generator obeying ExternalStall
// Timing rule used everywhere: drive 1 ns after posedge, sample at posedge.
//-----------------------------------------------------------------------------
`timescale 1ns/1ps

// ---------------------------------------------------------------- slave ----
// Memory map (index = {addr[31:28], addr[13:2]}, 4 KB window per top nibble):
//   0xE*******  : 2-cycle ERROR response (read data 0)
//   0xC*******  : poll counter: a read returns cnt then cnt++ ; a write sets cnt
//   other       : RAM
module ahb_mem_slave (
  input  wire        clk, rstn,
  input  wire [31:0] HADDR,
  input  wire [1:0]  HTRANS,
  input  wire        HWRITE,
  input  wire [2:0]  HSIZE,
  input  wire [2:0]  HBURST,
  input  wire [3:0]  HPROT,
  input  wire [31:0] HWDATA,
  output reg  [31:0] HRDATA,
  output wire        HREADY,
  output reg         HRESP
);
  reg [31:0] mem [0:65535];
  reg [31:0] poll_cnt;
  integer    max_wait;            // set by the test: 0 = zero-wait slave
  integer    viol;                // protocol violations seen on the slave bus
  integer    xfers;

  function automatic [15:0] idx(input [31:0] a); idx = {a[31:28], a[13:2]}; endfunction

  // data phase state
  reg        dp_v, dp_w, dp_err, dp_poll; reg [31:0] dp_a; reg [2:0] dp_s; reg [3:0] dp_prot;
  integer    dp_wait; reg err2;
  assign HREADY = !dp_v || (dp_wait == 0 && (!dp_err || err2));

  initial begin max_wait = 0; viol = 0; xfers = 0; poll_cnt = 0; dp_v = 0; dp_wait = 0; err2 = 0; end

  // previous-cycle values for the stability checks
  reg pw; reg [31:0] pa; reg [1:0] pt; reg pwr; reg [2:0] ps;

  always @(posedge clk or negedge rstn) begin
    if (!rstn) begin dp_v <= 0; dp_wait <= 0; err2 <= 0; pw <= 0; end
    else begin
      // ---- slave-side protocol checks (mux output acts as the master here)
      if (pw && pt[1] && (HTRANS !== pt || HADDR !== pa || HWRITE !== pwr || HSIZE !== ps)) begin
        viol = viol + 1; $display("  [SLV-RULE] %0t address/control changed during a wait state", $time); end
      if (HTRANS[1] && (HADDR & ((32'h1 << HSIZE) - 1)) != 0) begin viol = viol + 1; $display("  [SLV-RULE] %0t unaligned HADDR %h HSIZE %0d", $time, HADDR, HSIZE); end
      if (HTRANS[1] && HSIZE > 3'd2) begin viol = viol + 1; $display("  [SLV-RULE] %0t HSIZE > word", $time); end
      if (HTRANS == 2'b01) begin viol = viol + 1; $display("  [SLV-RULE] %0t BUSY on a single-transfer bus", $time); end
      if (HTRANS[1] && HBURST !== 3'b000) begin viol = viol + 1; $display("  [SLV-RULE] %0t mux forwarded HBURST=%b (expect SINGLE)", $time, HBURST); end
      if ((^{HTRANS}) === 1'bx || (HTRANS[1] && (^{HADDR, HWRITE, HSIZE}) === 1'bx)) begin viol = viol + 1; $display("  [SLV-RULE] %0t X on slave bus", $time); end
      pw <= !HREADY; pa <= HADDR; pt <= HTRANS; pwr <= HWRITE; ps <= HSIZE;

      // ---- data phase
      if (dp_v) begin
        if (dp_wait > 0) dp_wait <= dp_wait - 1;
        else if (dp_err && !err2) begin err2 <= 1; end
        else begin
          // completes this cycle
          if (dp_poll && !dp_err) poll_cnt <= dp_w ? HWDATA : poll_cnt + 1;
          if (dp_w && !dp_err) begin
            if ((^HWDATA) === 1'bx) begin viol = viol + 1; $display("  [SLV-RULE] %0t X on HWDATA", $time); end
            if (!dp_poll) case (dp_s)
              3'd0: mem[idx(dp_a)][8*dp_a[1:0] +: 8]  <= HWDATA[8*dp_a[1:0] +: 8];
              3'd1: mem[idx(dp_a)][16*dp_a[1]  +: 16] <= HWDATA[16*dp_a[1] +: 16];
              default: mem[idx(dp_a)] <= HWDATA;
            endcase
          end
          dp_v <= 0; err2 <= 0;
        end
      end
      // ---- address phase accepted
      if (HREADY && HTRANS[1]) begin
        xfers = xfers + 1;
        dp_v <= 1; dp_a <= HADDR; dp_w <= HWRITE; dp_s <= HSIZE; dp_prot <= HPROT;
        dp_err  <= (HADDR[31:28] == 4'hE);
        dp_poll <= (HADDR[31:28] == 4'hC);
        dp_wait <= (max_wait > 0) ? $urandom_range(max_wait, 0) : 0;
        err2 <= 0;
      end
    end
  end
  // read data / response, combinational from the data phase
  always @(*) begin
    HRDATA = 32'h0;
    if (dp_v && !dp_w && !dp_err) HRDATA = dp_poll ? poll_cnt : mem[idx(dp_a)];
    HRESP  = dp_v && dp_err && (dp_wait == 0);
  end
endmodule

// ---------------------------------------------------------- core master ----
// Random single transfers into 0x9000_0000..0x9000_0FFF (its private window)
// plus occasional accesses to the ERROR window 0xE900_0000 (must get ERROR).
// HPROT = 4'b0010 so the slave-side monitor can tell core from debugger.
module ahb_core_master (
  input  wire        clk, rstn,
  output reg  [31:0] HADDR,
  output reg  [1:0]  HTRANS,
  output reg         HWRITE,
  output reg  [2:0]  HSIZE,
  output wire [2:0]  HBURST,
  output wire [3:0]  HPROT,
  output wire        HMASTLOCK,
  output reg  [31:0] HWDATA,
  input  wire [31:0] HRDATA,
  input  wire        HREADY,
  input  wire        HRESP
);
  assign HBURST = 3'b000; assign HPROT = 4'b0010; assign HMASTLOCK = 1'b0;
  reg [31:0] shadow [0:1023];
  integer enable, busy_pct, done_n, rd_ok, rd_bad, err_ok, err_bad, wr_n, viol;
  reg ap_v, ap_w, ap_e; reg [31:0] ap_a, ap_d; reg [2:0] ap_s;
  reg dp_v, dp_w, dp_e; reg [31:0] dp_a, dp_d; reg [2:0] dp_s;
  integer k;
  initial begin
    enable = 0; busy_pct = 70; done_n = 0; rd_ok = 0; rd_bad = 0; err_ok = 0; err_bad = 0; wr_n = 0; viol = 0;
    for (k = 0; k < 1024; k++) shadow[k] = 32'h0;
    HTRANS = 0; HADDR = 0; HWRITE = 0; HSIZE = 2; HWDATA = 0; ap_v = 0; dp_v = 0;
  end
  function automatic [31:0] lane_merge(input [31:0] old, input [31:0] nd, input [1:0] a, input [2:0] s);
    lane_merge = old;
    case (s) 3'd0: lane_merge[8*a +: 8] = nd[8*a +: 8]; 3'd1: lane_merge[16*a[1] +: 16] = nd[16*a[1] +: 16]; default: lane_merge = nd; endcase
  endfunction
  task automatic new_ap();
    reg [1:0] s; reg [31:0] a; reg [31:0] d;
    begin
      if (enable && $urandom_range(99, 0) < busy_pct) begin
        s = $urandom_range(2, 0); if (s == 3) s = 2;
        a = 32'h9000_0000 | ($urandom_range(1023, 0) << 2);
        if (s == 0) a[1:0] = $urandom_range(3, 0); else if (s == 1) a[1] = $urandom_range(1, 0);
        d = $urandom;
        ap_v = 1; ap_w = $urandom_range(1, 0); ap_s = s; ap_a = a; ap_d = d; ap_e = 0;
        if ($urandom_range(49, 0) == 0) begin ap_a = 32'hE900_0000 | ($urandom_range(255, 0) << 2); ap_s = 2; ap_e = 1; end
      end else ap_v = 0;
    end
  endtask
  // stability of a waited request (core side of the mux)
  reg was_wait; reg [36:0] prev;
  always @(posedge clk) begin
    if (rstn && was_wait && prev !== {HTRANS[1], HADDR, HWRITE, HSIZE[1:0]}) begin viol++; $display("  [M0-RULE] %0t core request changed while waited", $time); end
    was_wait = HTRANS[1] && !HREADY; prev = {HTRANS[1], HADDR, HWRITE, HSIZE[1:0]};
  end
  always begin
    @(posedge clk);
    if (!rstn) begin ap_v = 0; dp_v = 0; #1 HTRANS = 0; end
    else if (HREADY) begin
      if (dp_v) begin                                   // data phase completes at this edge
        done_n++;
        if (dp_e) begin if (HRESP) err_ok++; else begin err_bad++; $display("  [M0] %0t expected ERROR at %h, got OKAY", $time, dp_a); end end
        else if (HRESP) begin err_bad++; $display("  [M0] %0t unexpected ERROR at %h", $time, dp_a); end
        else if (dp_w) begin shadow[dp_a[11:2]] = lane_merge(shadow[dp_a[11:2]], dp_d, dp_a[1:0], dp_s); wr_n++; end
        else begin
          if (((HRDATA ^ shadow[dp_a[11:2]]) & ((dp_s == 0) ? (32'hFF << 8*dp_a[1:0]) : (dp_s == 1) ? (32'hFFFF << 16*dp_a[1]) : 32'hFFFF_FFFF)) == 0) rd_ok++;
          else begin rd_bad++; $display("  [M0] %0t read %h got %h expected %h", $time, dp_a, HRDATA, shadow[dp_a[11:2]]); end
        end
      end
      dp_v = ap_v; dp_w = ap_w; dp_a = ap_a; dp_d = ap_d; dp_s = ap_s; dp_e = ap_e;
      new_ap();
      #1;
      HTRANS = ap_v ? 2'b10 : 2'b00; HADDR = ap_v ? ap_a : HADDR; HWRITE = ap_v ? ap_w : 1'b0; HSIZE = ap_v ? ap_s : 3'd2;
      HWDATA = dp_v ? (dp_s == 0 ? {4{dp_d[8*dp_a[1:0] +: 8]}} : dp_s == 1 ? {2{dp_d[16*dp_a[1] +: 16]}} : dp_d) : 32'h0;
      if (dp_v && dp_s == 0) dp_d = {4{dp_d[8*dp_a[1:0] +: 8]}};
      if (dp_v && dp_s == 1) dp_d = {2{dp_d[16*dp_a[1] +: 16]}};
    end else begin
      // HREADY low: hold everything (AHB rule)
      #1;
    end
  end
endmodule

// ------------------------------------------------------------- fake core ----
// Emits a 1-cycle "instruction retired" pulse every `period` cycles while it is
// not stalled. period = 0 -> never retires (used to hit the step watchdog).
// Like the real core, the retire strobe is combinationally gated by the stall
// (InstrRetired = ValidM & ~StallW): an instruction that is ready waits while stalled.
module fake_core (input wire clk, rstn, stall, output wire retired);
  integer period, cnt, retire_total, free_cycles;
  reg pend, r;
  assign retired = pend && !stall;
  initial begin period = 3; cnt = 0; pend = 0; retire_total = 0; free_cycles = 0; end
  always @(posedge clk) begin
    if (!rstn) begin cnt = 0; #1 pend = 0; end
    else begin
      r = retired;                                       // value during the cycle that just ended
      if (r) retire_total++;
      if (!stall) free_cycles++;
      if (!pend && period != 0 && !stall) cnt = cnt + 1;
      #1;
      if (r) pend = 0;
      else if (!pend && period != 0 && cnt >= period) begin pend = 1; cnt = 0; end
    end
  end
endmodule
