//-----------------------------------------------------------------------------
// 2-Master AHB-Lite Bus Arbiter and Multiplexer
// Connects RISC-V CPU Core (Master 0) and SoCDebug (Master 1)
// to Downstream Memory & Peripherals (Uncore + Accelerator)
//-----------------------------------------------------------------------------
//-----------------------------------------------------------------------------
// 2-Master AHB-Lite Bus Arbiter and Multiplexer  (FIXED version)
// Master 0: RISC-V core   Master 1: SoCDebug
//
// Why the original lost transfers:
//   HREADY is one signal for two meanings: "your data phase is done" AND
//   "your next address is accepted". The original gave a master HREADY=1
//   to finish its data phase in a cycle where the *other* master owned the
//   address phase, so that master's new address was silently dropped.
//
// Fix: AHB "input stage" per master.
//   - A master that is not waiting always gets HREADY = S_HREADY.
//   - If its address is accepted from its point of view but another master
//     owns the address phase that cycle, the transfer is captured into a
//     1-deep hold buffer and replayed later (held transfers have priority).
//   - While a master's held transfer is outstanding, the master is kept in a
//     waited data phase (HREADY=0) until the slave completes that transfer.
//   - The selection is frozen while the slave inserts wait states, so the
//     slave bus never changes address in the middle of a waited transfer.
//   - Mx_HREADY never depends on Mx_HTRANS -> no combinational loop with the
//     core, whose HTRANS depends combinationally on HREADY.
// Priority: held(M1) > held(M0) > live M1 (debugger) > live M0 (core).
// Every master is served at least every other cycle -> no starvation.
// Every forwarded transfer is a single NONSEQ transfer (HBURST = SINGLE).
// HMASTLOCK is forwarded but not honoured (both masters tie it to 0).
//-----------------------------------------------------------------------------
module ahb_mux #(
        parameter ADDR_WIDTH = 32,
        parameter DATA_WIDTH = 32
    )(
        input  wire                  HCLK,
        input  wire                  HRESETn,
        // Master 0: core
        input  wire [ADDR_WIDTH-1:0] M0_HADDR,
        input  wire [DATA_WIDTH-1:0] M0_HWDATA,
        input  wire                  M0_HWRITE,
        input  wire [1:0]            M0_HTRANS,
        input  wire [2:0]            M0_HSIZE,
        input  wire [2:0]            M0_HBURST,
        input  wire [3:0]            M0_HPROT,
        input  wire                  M0_HMASTLOCK,
        output wire [DATA_WIDTH-1:0] M0_HRDATA,
        output wire                  M0_HREADY,
        output wire                  M0_HRESP,
        // Master 1: debugger
        input  wire [ADDR_WIDTH-1:0] M1_HADDR,
        input  wire [DATA_WIDTH-1:0] M1_HWDATA,
        input  wire                  M1_HWRITE,
        input  wire [1:0]            M1_HTRANS,
        input  wire [2:0]            M1_HSIZE,
        input  wire [2:0]            M1_HBURST,
        input  wire [3:0]            M1_HPROT,
        input  wire                  M1_HMASTLOCK,
        output wire [DATA_WIDTH-1:0] M1_HRDATA,
        output wire                  M1_HREADY,
        output wire                  M1_HRESP,
        // Slave side
        output wire [ADDR_WIDTH-1:0] S_HADDR,
        output wire [DATA_WIDTH-1:0] S_HWDATA,
        output wire                  S_HWRITE,
        output wire [1:0]            S_HTRANS,
        output wire [2:0]            S_HSIZE,
        output wire [2:0]            S_HBURST,
        output wire [3:0]            S_HPROT,
        output wire                  S_HMASTLOCK,
        input  wire [DATA_WIDTH-1:0] S_HRDATA,
        input  wire                  S_HREADY,
        input  wire                  S_HRESP,
        // Data-phase owner: 0 = core, 1 = debugger (drives HWDATA/HWSTRB select)
        output wire                  grant_data
    );

    localparam CW = ADDR_WIDTH + 1 + 3 + 4 + 1;      // addr, write, size, prot, lock

    // address-phase sources
    localparam [2:0] SRC_NONE = 3'd0, SRC_M0 = 3'd1, SRC_M1 = 3'd2, SRC_H0 = 3'd3, SRC_H1 = 3'd4;

    wire m0_req = M0_HTRANS[1];
    wire m1_req = M1_HTRANS[1];

    wire [CW-1:0] m0_ctrl = {M0_HADDR, M0_HWRITE, M0_HSIZE, M0_HPROT, M0_HMASTLOCK};
    wire [CW-1:0] m1_ctrl = {M1_HADDR, M1_HWRITE, M1_HSIZE, M1_HPROT, M1_HMASTLOCK};
    // Not needed: every transfer is forwarded as a single NONSEQ (HTRANS[0] only
    // separates SEQ from NONSEQ, HBURST only describes bursts)
    wire unused_ok = &{1'b0, M0_HBURST, M1_HBURST, M0_HTRANS[0], M1_HTRANS[0]};

    // hold buffers
    reg          h0_vld, h1_vld;
    reg [CW-1:0] h0_ctrl, h1_ctrl;
    // master waiting for its held transfer to finish on the slave
    reg          m0_wait, m1_wait;
    // slave data phase tracking
    reg          dp_vld, dp_own, dp_held;    // dp_own: 0=M0, 1=M1
    // selection freeze during slave wait states
    reg          lock;
    reg [2:0]    sel_q;

    // A waiting master's live address may only go out in the cycle its held transfer completes
    wire m0_held_done_now = dp_vld && !dp_own && dp_held;
    wire m1_held_done_now = dp_vld &&  dp_own && dp_held;
    wire m0_live_ok = !m0_wait || m0_held_done_now;
    wire m1_live_ok = !m1_wait || m1_held_done_now;

    reg [2:0] sel_c;
    always @(*) begin
        if      (h1_vld)                 sel_c = SRC_H1;
        else if (h0_vld)                 sel_c = SRC_H0;
        else if (m1_req && m1_live_ok)   sel_c = SRC_M1;
        else if (m0_req && m0_live_ok)   sel_c = SRC_M0;
        else                             sel_c = SRC_NONE;
    end
    wire [2:0] sel = lock ? sel_q : sel_c;

    // master-side HREADY: never a function of the master's own HTRANS
    assign M0_HREADY = m0_wait ? (m0_held_done_now ? S_HREADY : 1'b0) : S_HREADY;
    assign M1_HREADY = m1_wait ? (m1_held_done_now ? S_HREADY : 1'b0) : S_HREADY;

    // address phase to slave
    reg [CW-1:0] s_ctrl;
    always @(*) begin
        case (sel)
            SRC_M0:  s_ctrl = m0_ctrl;
            SRC_M1:  s_ctrl = m1_ctrl;
            SRC_H0:  s_ctrl = h0_ctrl;
            SRC_H1:  s_ctrl = h1_ctrl;
            default: s_ctrl = m0_ctrl;
        endcase
    end
    assign {S_HADDR, S_HWRITE, S_HSIZE, S_HPROT, S_HMASTLOCK} = s_ctrl;
    // Transfers of the two masters can interleave, so a SEQ beat could follow the
    // other master's transfer on the slave bus (illegal). Every forwarded
    // transfer is therefore sent as a single NONSEQ transfer.
    assign S_HTRANS = (sel == SRC_NONE) ? 2'b00 : 2'b10;   // IDLE or NONSEQ
    assign S_HBURST = 3'b000;                               // SINGLE

    // capture: master sees its address accepted (HREADY=1) but it is not the one on the slave bus
    wire cap0 = S_HREADY && M0_HREADY && m0_req && (sel != SRC_M0);
    wire cap1 = S_HREADY && M1_HREADY && m1_req && (sel != SRC_M1);

    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            h0_vld <= 1'b0; h1_vld <= 1'b0; h0_ctrl <= {CW{1'b0}}; h1_ctrl <= {CW{1'b0}};
            m0_wait <= 1'b0; m1_wait <= 1'b0;
            dp_vld <= 1'b0; dp_own <= 1'b0; dp_held <= 1'b0;
            lock <= 1'b0; sel_q <= SRC_NONE;
        end else begin
            sel_q <= sel;
            lock  <= S_HTRANS[1] && !S_HREADY;              // keep the same address while the slave waits
            if (S_HREADY) begin
                // hold buffers: capture / drain
                if (cap0) begin h0_vld <= 1'b1; h0_ctrl <= m0_ctrl; end
                else if (sel == SRC_H0) h0_vld <= 1'b0;
                if (cap1) begin h1_vld <= 1'b1; h1_ctrl <= m1_ctrl; end
                else if (sel == SRC_H1) h1_vld <= 1'b0;
                // wait flags: set on capture, clear when the held transfer's data phase completes
                if (cap0) m0_wait <= 1'b1; else if (m0_held_done_now) m0_wait <= 1'b0;
                if (cap1) m1_wait <= 1'b1; else if (m1_held_done_now) m1_wait <= 1'b0;
                // slave data phase owner
                dp_vld  <= S_HTRANS[1];
                dp_own  <= (sel == SRC_M1) || (sel == SRC_H1);
                dp_held <= (sel == SRC_H0) || (sel == SRC_H1);
            end
        end
    end

    // data phase routing
    assign grant_data = dp_own;
    assign S_HWDATA   = dp_own ? M1_HWDATA : M0_HWDATA;
    assign M0_HRDATA  = S_HRDATA;
    assign M1_HRDATA  = S_HRDATA;
    assign M0_HRESP   = (dp_vld && !dp_own) ? S_HRESP : 1'b0;
    assign M1_HRESP   = (dp_vld &&  dp_own) ? S_HRESP : 1'b0;

endmodule

