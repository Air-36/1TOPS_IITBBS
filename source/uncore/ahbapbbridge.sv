// ahbapbbridge.sv
// Purpose: AMBA 3 AHB-Lite to APB 3 Bridge

module ahbapbbridge #(
        parameter XLEN    = 32,
        parameter PERIPHS = 4
    )(
        input  logic                      HCLK,
        input  logic                      HRESETn,
        input  logic [PERIPHS-1:0]        HSEL,
        input  logic [31:0]               HADDR,
        input  logic [XLEN-1:0]           HWDATA,
        input  logic [XLEN/8-1:0]         HWSTRB,
        input  logic                      HWRITE,
        input  logic [ 1:0]               HTRANS,
        input  logic                      HREADY,
        output logic [XLEN-1:0]           HRDATA,
        output logic                      HRESP,
        output logic                      HREADYOUT,

        // APB Master Bus
        output logic                      PCLK,
        output logic                      PRESETn,
        output logic [PERIPHS-1:0]        PSEL,
        output logic                      PWRITE,
        output logic                      PENABLE,
        output logic [31:0]               PADDR,
        output logic [XLEN-1:0]           PWDATA,
        output logic [XLEN/8-1:0]         PSTRB,
        input  logic [PERIPHS-1:0]        PREADY,
        input  logic [PERIPHS*XLEN-1:0]   PRDATA
    );

    assign PCLK    = HCLK;
    assign PRESETn = HRESETn;

    logic initTrans;
    logic initTransSel;
    logic initTransSelD;
    logic PREADYOUT;

    assign initTrans    = HTRANS[1] & HREADY;
    assign initTransSel = initTrans & (|HSEL);

    // Delay AHB Address phase signals to align with APB setup phase
    always_ff @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            PADDR         <= 32'd0;
            PWRITE        <= 1'b0;
            PSEL          <= '0;
            initTransSelD <= 1'b0;
            PENABLE       <= 1'b0;
        end else begin
            if (HREADY) begin
                PADDR  <= HADDR;
                PWRITE <= HWRITE;
                PSEL   <= HSEL & {PERIPHS{initTrans}};
            end
            initTransSelD <= initTransSel;
            PENABLE       <= PENABLE ? ~HREADY : initTransSelD;
        end
    end

    assign PWDATA = HWDATA;
    assign PSTRB  = HWSTRB;

    localparam int SEL_WIDTH = (PERIPHS > 1) ? $clog2(PERIPHS) : 1;

    // Multiplex read data and ready signals from selected APB peripheral
    function automatic logic [SEL_WIDTH-1:0] get_sel_idx(input logic [PERIPHS-1:0] sel);
        logic [SEL_WIDTH-1:0] idx;
        idx = '0;
        for (int i = 0; i < PERIPHS; i++) begin
            if (sel[i]) idx = SEL_WIDTH'(i);
        end
        return idx;
    endfunction

    wire [SEL_WIDTH-1:0] sel_idx = get_sel_idx(PSEL);
    assign HRDATA    = (|PSEL) ? PRDATA[sel_idx*XLEN +: XLEN] : '0;
    assign PREADYOUT = (|PSEL) ? PREADY[sel_idx] : 1'b1;

    // Hold HREADYOUT low during setup cycle, release when APB access phase completes
    assign HREADYOUT = PREADYOUT & ~initTransSelD;
    assign HRESP     = 1'b0; // Bridge returns OKAY

endmodule
