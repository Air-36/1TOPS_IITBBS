// =============================================================================
// Testbench: tb_sysctrl_unit
// Purpose: Top-level Testbench for SysCtrl IP Unit Verification
// =============================================================================

`timescale 1ns/1ps

import uvm_pkg::*;
`include "uvm_macros.svh"
import apb_pkg::*;

`include "sysctrl_unit_env.sv"
`include "sysctrl_unit_test.sv"

module tb_sysctrl_unit;

    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import apb_pkg::*;

    logic clk;
    logic rst_n;

    initial clk = 0;
    always #10 clk = ~clk;

    initial begin
        rst_n = 0;
        #50;
        rst_n = 1;
    end

    apb_if #(32, 32) apb_vif (clk, rst_n);

    sysctrl_apb #(
        .XLEN(32)
    ) dut (
        .PCLK(clk),
        .PRESETn(rst_n),
        .PSEL(apb_vif.PSEL),
        .PADDR(apb_vif.PADDR[7:0]),
        .PWDATA(apb_vif.PWDATA),
        .PSTRB(apb_vif.PSTRB),
        .PWRITE(apb_vif.PWRITE),
        .PENABLE(apb_vif.PENABLE),
        .PREADY(apb_vif.PREADY),
        .PRDATA(apb_vif.PRDATA),
        .boot_mode_pin(1'b0),
        .dbg_core_reset_i(1'b0),
        .soft_core_rst_n_o(),
        .soft_periph_rst_n_o(),
        .boot_mode_latched_o(),
        .boot_mode_live_o(),
        .remap_en_o(),
        .reset_vector_o(),
        .clk_gate_mask_o()
    );

    initial begin
        apb_vif.PSLVERR = 1'b0;
    end

    initial begin
        uvm_config_db#(virtual apb_if#(32, 32))::set(null, "uvm_test_top.env.apb_ag*",  "vif", apb_vif);
        uvm_config_db#(virtual apb_if#(32, 32))::set(null, "uvm_test_top.env",          "apb_vif", apb_vif);
        run_test();
    end

endmodule

