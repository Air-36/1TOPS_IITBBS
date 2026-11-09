// =============================================================================
// Testbench: tb_plic_unit
// Purpose: Top-level Testbench for PLIC IP Unit Verification
// =============================================================================

`timescale 1ns/1ps

import uvm_pkg::*;
`include "uvm_macros.svh"
import apb_pkg::*;
import irq_pkg::*;

`include "plic_unit_env.sv"
`include "plic_unit_test.sv"

module tb_plic_unit;

    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import apb_pkg::*;
    import irq_pkg::*;

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
    irq_if          irq_vif (clk, rst_n);

    // DUT Instantiation
    plic_apb #(
        .XLEN(32)
    ) dut (
        .PCLK(clk),
        .PRESETn(rst_n),
        .PSEL(apb_vif.PSEL),
        .PADDR(apb_vif.PADDR[27:0]),
        .PWDATA(apb_vif.PWDATA),
        .PWRITE(apb_vif.PWRITE),
        .PENABLE(apb_vif.PENABLE),
        .PRDATA(apb_vif.PRDATA),
        .PREADY(apb_vif.PREADY),
        .UARTIntr(irq_vif.uart_intr),
        .GPIOIntr(irq_vif.gpio_intr),
        .SPIIntr(irq_vif.spi_intr),
        .SDCIntr(irq_vif.sdc_intr),
        .MExtInt(irq_vif.mext_int),
        .SExtInt(irq_vif.sext_int)
    );

    initial begin
        apb_vif.PSLVERR   = 1'b0;
        irq_vif.mtimer_int = 1'b0;
        irq_vif.msw_int    = 1'b0;
        irq_vif.uart_intr  = 1'b0;
        irq_vif.gpio_intr  = 1'b0;
        irq_vif.spi_intr   = 1'b0;
        irq_vif.sdc_intr   = 1'b0;
    end

    initial begin
        uvm_config_db#(virtual apb_if#(32, 32))::set(null, "uvm_test_top.env.apb_ag*",  "vif", apb_vif);
        uvm_config_db#(virtual irq_if)::set(null,          "uvm_test_top.env.irq_ag*",  "vif", irq_vif);
        uvm_config_db#(virtual apb_if#(32, 32))::set(null, "uvm_test_top.env",          "apb_vif", apb_vif);
        uvm_config_db#(virtual irq_if)::set(null,          "uvm_test_top.env",          "irq_vif", irq_vif);

        run_test();
    end

endmodule

