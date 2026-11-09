// =============================================================================
// Interface: apb_if
// Purpose: AMBA 3 APB Master Interface Definition
// =============================================================================

`ifndef APB_IF_SV
`define APB_IF_SV

interface apb_if #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
)(
    input logic PCLK,
    input logic PRESETn
);

    logic                  PSEL;
    logic                  PENABLE;
    logic                  PWRITE;
    logic [ADDR_WIDTH-1:0] PADDR;
    logic [DATA_WIDTH-1:0] PWDATA;
    logic [DATA_WIDTH/8-1:0] PSTRB;
    logic [DATA_WIDTH-1:0] PRDATA;
    logic                  PREADY;
    logic                  PSLVERR;

    // Master Clocking Block
    clocking master_cb @(posedge PCLK);
        default input #1step output #1ns;
        output PSEL, PENABLE, PWRITE, PADDR, PWDATA, PSTRB;
        input  PRDATA, PREADY, PSLVERR;
    endclocking

    // Monitor Clocking Block
    clocking mon_cb @(posedge PCLK);
        default input #1step;
        input PSEL, PENABLE, PWRITE, PADDR, PWDATA, PSTRB;
        input PRDATA, PREADY, PSLVERR;
    endclocking

    modport master  (clocking master_cb, input PRESETn);
    modport monitor (clocking mon_cb,    input PRESETn);

endinterface : apb_if

`endif // APB_IF_SV

