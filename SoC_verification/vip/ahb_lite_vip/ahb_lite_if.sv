// =============================================================================
// Interface: ahb_lite_if
// Purpose: AMBA 3 AHB-Lite Master Interface Definition
// =============================================================================

`ifndef AHB_LITE_IF_SV
`define AHB_LITE_IF_SV

interface ahb_lite_if #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
)(
    input logic HCLK,
    input logic HRESETn
);

    // AHB Address & Control
    logic [ADDR_WIDTH-1:0] HADDR;
    logic [DATA_WIDTH-1:0] HWDATA;
    logic [DATA_WIDTH/8-1:0] HWSTRB;
    logic                  HWRITE;
    logic [1:0]            HTRANS;
    logic [2:0]            HSIZE;
    logic [2:0]            HBURST;
    logic [3:0]            HPROT;
    logic                  HMASTLOCK;

    // AHB Response from Slaves / Bus Interconnect
    logic [DATA_WIDTH-1:0] HRDATA;
    logic                  HREADY;
    logic                  HRESP;

    // Master Clocking Block
    clocking master_cb @(posedge HCLK);
        default input #1step output #1ns;
        output HADDR, HWDATA, HWSTRB, HWRITE, HTRANS, HSIZE, HBURST, HPROT, HMASTLOCK;
        input  HRDATA, HREADY, HRESP;
    endclocking

    // Monitor Clocking Block
    clocking mon_cb @(posedge HCLK);
        default input #1step;
        input HADDR, HWDATA, HWSTRB, HWRITE, HTRANS, HSIZE, HBURST, HPROT, HMASTLOCK;
        input HRDATA, HREADY, HRESP;
    endclocking

    // Modports
    modport master (clocking master_cb, input HRESETn);
    modport monitor (clocking mon_cb, input HRESETn);

endinterface : ahb_lite_if

`endif // AHB_LITE_IF_SV

