// =============================================================================
// Testbench: tb_gpio_unit
// Purpose: Top-level Testbench for GPIO IP Unit Verification
// =============================================================================

`timescale 1ns/1ps

import uvm_pkg::*;
`include "uvm_macros.svh"
import apb_pkg::*;
import gpio_pkg::*;

`include "gpio_unit_env.sv"
`include "gpio_unit_test.sv"

module tb_gpio_unit;

    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import apb_pkg::*;
    import gpio_pkg::*;

    logic clk;
    logic rst_n;

    // Clock generation (50 MHz)
    initial clk = 0;
    always #10 clk = ~clk;

    // Reset sequence
    initial begin
        rst_n = 0;
        #50;
        rst_n = 1;
    end

    // Interfaces
    apb_if #(32, 32) apb_vif (clk, rst_n);
    gpio_if          gpio_vif (clk, rst_n);

    // DUT Instantiation
    gpio_apb #(
        .XLEN(32)
    ) dut (
        .PCLK(clk),
        .PRESETn(rst_n),
        .PSEL(apb_vif.PSEL),
        .PADDR(apb_vif.PADDR[7:0]),
        .PWDATA(apb_vif.PWDATA),
        .PWRITE(apb_vif.PWRITE),
        .PENABLE(apb_vif.PENABLE),
        .PRDATA(apb_vif.PRDATA),
        .PREADY(apb_vif.PREADY),
        .GPIOIN(gpio_vif.gpio_in),
        .GPIOOUT(gpio_vif.gpio_out),
        .GPIOEN(gpio_vif.gpio_en),
        .GPIOIntr(gpio_vif.gpio_intr)
    );

    initial begin
        apb_vif.PSLVERR = 1'b0;
    end

    initial begin
        uvm_config_db#(virtual apb_if#(32, 32))::set(null, "uvm_test_top.env.apb_ag*",  "vif", apb_vif);
        uvm_config_db#(virtual gpio_if)::set(null,          "uvm_test_top.env.gpio_ag*", "vif", gpio_vif);
        uvm_config_db#(virtual apb_if#(32, 32))::set(null, "uvm_test_top.env",          "apb_vif", apb_vif);
        uvm_config_db#(virtual gpio_if)::set(null,          "uvm_test_top.env",          "gpio_vif", gpio_vif);

        run_test();
    end

endmodule
