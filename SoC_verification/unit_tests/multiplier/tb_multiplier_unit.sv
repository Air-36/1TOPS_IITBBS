// =============================================================================
// Testbench: tb_multiplier_unit
// Purpose: Top-level Testbench for Multiplier AHB Slave Unit Verification
// =============================================================================

`timescale 1ns/1ps

import uvm_pkg::*;
`include "uvm_macros.svh"
import ahb_lite_pkg::*;

`include "multiplier_unit_env.sv"
`include "multiplier_unit_test.sv"

module tb_multiplier_unit;

    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import ahb_lite_pkg::*;

    logic clk;
    logic rst_n;
    logic reset;

    initial clk = 0;
    always #10 clk = ~clk;

    initial begin
        rst_n = 0;
        reset = 1;
        #50;
        rst_n = 1;
        reset = 0;
    end

    ahb_lite_if #(32, 32) ahb_vif (clk, rst_n);

    // Multiplier Slave DUT
    multiplier_ahb #(
        .XLEN(32)
    ) dut (
        .clk(clk),
        .reset(reset),
        .HSEL(1'b1), // Dedicated unit test: always selected
        .HADDR(ahb_vif.HADDR),
        .HWDATA(ahb_vif.HWDATA),
        .HWRITE(ahb_vif.HWRITE),
        .HTRANS(ahb_vif.HTRANS),
        .HREADY(ahb_vif.HREADY),
        .HREADYOUT(ahb_vif.HREADY),
        .HRESP(ahb_vif.HRESP),
        .HRDATA(ahb_vif.HRDATA)
    );

    initial begin
        uvm_config_db#(virtual ahb_lite_if#(32, 32))::set(null, "uvm_test_top.env.ahb_ag*",  "vif", ahb_vif);
        uvm_config_db#(virtual ahb_lite_if#(32, 32))::set(null, "uvm_test_top.env",          "ahb_vif", ahb_vif);
        run_test();
    end

endmodule

