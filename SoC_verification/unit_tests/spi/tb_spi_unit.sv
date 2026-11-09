// =============================================================================
// Testbench: tb_spi_unit
// Purpose: Top-level Testbench for SPI IP Unit Verification
// =============================================================================

`timescale 1ns/1ps

import uvm_pkg::*;
`include "uvm_macros.svh"
import apb_pkg::*;
import irq_pkg::*;

`include "spi_unit_env.sv"
`include "spi_unit_test.sv"

module tb_spi_unit;

    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import apb_pkg::*;
    import irq_pkg::*;

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
    irq_if          irq_vif (clk, rst_n);

    spi_apb #(
        .XLEN(32),
        .SPI_LOOPBACK_TEST(0)
    ) dut (
        .PCLK(clk),
        .PRESETn(rst_n),
        .PSEL(apb_vif.PSEL),
        .PADDR(apb_vif.PADDR[7:0]),
        .PWDATA(apb_vif.PWDATA),
        .PWRITE(apb_vif.PWRITE),
        .PENABLE(apb_vif.PENABLE),
        .PREADY(apb_vif.PREADY),
        .PRDATA(apb_vif.PRDATA),
        .SPIOut(),
        .SPIIn(1'b0),
        .SPICS(),
        .SPIIntr(irq_vif.spi_intr),
        .SPICLK()
    );

    initial begin
        apb_vif.PSLVERR   = 1'b0;
        irq_vif.mtimer_int = 1'b0;
        irq_vif.msw_int    = 1'b0;
        irq_vif.mext_int   = 1'b0;
        irq_vif.sext_int   = 1'b0;
        irq_vif.uart_intr  = 1'b0;
        irq_vif.gpio_intr  = 1'b0;
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

