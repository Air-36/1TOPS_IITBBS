//-----------------------------------------------------------------------------
// Concurrent assertions (SVA) for the debugger subsystem - bound into the DUT.
// Run with Verilator (--assert). Icarus has no SVA support; the same rules are
// also checked procedurally inside tb_dbg_block.sv so both simulators cover them.
//-----------------------------------------------------------------------------
module sva_dbg_master (input logic clk, rst_n,
                       input logic [1:0] HTRANS, input logic [31:0] HADDR, HWDATA, input logic [2:0] HSIZE,
                       input logic HWRITE, HREADY);
  logic dphase_w;
  always_ff @(posedge clk or negedge rst_n) if (!rst_n) dphase_w <= 0; else if (HREADY) dphase_w <= HTRANS[1] && HWRITE;
  // AHB-Lite: a waited NONSEQ request must be held unchanged
  a_hold:   assert property (@(posedge clk) disable iff (!rst_n) HTRANS[1] && !HREADY |=> $stable({HTRANS, HADDR, HWRITE, HSIZE}));
  // write data held during an extended write data phase
  a_wdata:  assert property (@(posedge clk) disable iff (!rst_n) dphase_w && !HREADY |=> $stable(HWDATA));
  // single transfers only, aligned, <= word
  a_trans:  assert property (@(posedge clk) disable iff (!rst_n) HTRANS != 2'b01 && HTRANS != 2'b11);
  a_align:  assert property (@(posedge clk) disable iff (!rst_n) HTRANS[1] |-> HSIZE <= 3'd2 && (HADDR & ((32'h1 << HSIZE) - 1)) == 0);
  a_known:  assert property (@(posedge clk) disable iff (!rst_n) !$isunknown(HTRANS) && (!HTRANS[1] || !$isunknown({HADDR, HWRITE, HSIZE})));
endmodule

module sva_dbg_slavebus (input logic clk, rst_n, input logic [1:0] HTRANS, input logic [31:0] HADDR,
                         input logic [2:0] HSIZE, HBURST, input logic HWRITE, HREADY, HRESP);
  a_hold:   assert property (@(posedge clk) disable iff (!rst_n) HTRANS[1] && !HREADY |=> $stable({HTRANS, HADDR, HWRITE, HSIZE}));
  a_single: assert property (@(posedge clk) disable iff (!rst_n) HTRANS[1] |-> HBURST == 3'b000);
  // ERROR is a two-cycle response: first cycle HREADY low, second HREADY high
  a_err2:   assert property (@(posedge clk) disable iff (!rst_n) HRESP && !HREADY |=> HRESP && HREADY);
endmodule

module sva_step (input logic clk, rst_n, input logic [1:0] state, input logic core_stall_o, step_busy_o, step_done_o,
                 input logic halt_req_i, auto_halt_req_i, core_stall_ext_i);
  a_halted_stall: assert property (@(posedge clk) disable iff (!rst_n) state == 2'b01 |-> core_stall_o);
  a_done_stall:   assert property (@(posedge clk) disable iff (!rst_n) state == 2'b11 |-> core_stall_o && step_done_o);
  a_run_free:     assert property (@(posedge clk) disable iff (!rst_n) state == 2'b00 |-> core_stall_o == core_stall_ext_i);
  a_not_both:     assert property (@(posedge clk) disable iff (!rst_n) !(step_busy_o && step_done_o));
  a_done_pulse:   assert property (@(posedge clk) disable iff (!rst_n) step_done_o |=> !step_done_o);
  a_done_after:   assert property (@(posedge clk) disable iff (!rst_n) step_done_o |-> $past(step_busy_o));
  a_halt_reach:   assert property (@(posedge clk) disable iff (!rst_n) state == 2'b00 && halt_req_i |=> state == 2'b01);
endmodule

module sva_adp_stream (input logic clk, rst_n, input logic tx_valid, tx_ready, input logic [7:0] tx_data);
  // AXI-stream rule on the ADP -> UART/FT byte channel
  a_tx_hold: assert property (@(posedge clk) disable iff (!rst_n) tx_valid && !tx_ready |=> tx_valid && $stable(tx_data));
endmodule

bind riscv_debugger_top sva_dbg_master u_sva_m1 (.clk(clk), .rst_n(rst_n), .HTRANS(DEBUG_HTRANS), .HADDR(DEBUG_HADDR),
  .HWDATA(DEBUG_HWDATA), .HSIZE(DEBUG_HSIZE), .HWRITE(DEBUG_HWRITE), .HREADY(DEBUG_HREADY));
bind riscv_debugger_top sva_adp_stream u_sva_tx (.clk(clk), .rst_n(rst_n), .tx_valid(adp_txd_valid), .tx_ready(adp_txd_ready), .tx_data(adp_txd_data));
bind ahb_mux sva_dbg_slavebus u_sva_s (.clk(HCLK), .rst_n(HRESETn), .HTRANS(S_HTRANS), .HADDR(S_HADDR), .HSIZE(S_HSIZE),
  .HBURST(S_HBURST), .HWRITE(S_HWRITE), .HREADY(S_HREADY), .HRESP(S_HRESP));
bind core_step_controller sva_step u_sva_st (.clk(clk), .rst_n(rst_n), .state(state), .core_stall_o(core_stall_o),
  .step_busy_o(step_busy_o), .step_done_o(step_done_o), .halt_req_i(halt_req_i), .auto_halt_req_i(auto_halt_req_i), .core_stall_ext_i(core_stall_ext_i));
