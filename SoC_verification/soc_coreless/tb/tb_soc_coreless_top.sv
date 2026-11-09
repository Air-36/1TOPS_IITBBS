// =============================================================================
// Testbench: tb_soc_coreless_top
// Purpose: Top-level Testbench for Whole Coreless SoC UVM Verification
//          Connects:
//            - AMBA 3 AHB-Lite Master VIP to SoC Master Test Port
//            - GPIO VIP to SoC GPIO pins
//            - Interrupt Observation VIP to CLINT, PLIC, and Peripheral IRQs
//            - SPI Flash Behavioral Model to SoC SPI pins
//            - SVA AHB Protocol Checker for Formal Protocol Validation
// =============================================================================

`timescale 1ns/1ps

import uvm_pkg::*;
`include "uvm_macros.svh"
import ahb_lite_pkg::*;
import apb_pkg::*;
import gpio_pkg::*;
import irq_pkg::*;
import soc_coreless_env_pkg::*;
import soc_test_pkg::*;

module tb_soc_coreless_top;

    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import ahb_lite_pkg::*;
    import apb_pkg::*;
    import gpio_pkg::*;
    import irq_pkg::*;
    import soc_coreless_env_pkg::*;
    import soc_test_pkg::*;

    logic clk;
    logic rst_n;
    wire  reset = ~rst_n;

    // 50 MHz Master Clock
    initial clk = 0;
    always #10 clk = ~clk;

    // System Reset Sequence
    initial begin
        rst_n = 0;
        #60;
        rst_n = 1;
    end

    // -------------------------------------------------------------------------
    // VIP Interfaces Instantiation
    // -------------------------------------------------------------------------
    ahb_lite_if #(32, 32) ahb_vif  (clk, rst_n);
    gpio_if               gpio_vif (clk, rst_n);
    irq_if                irq_vif  (clk, rst_n);

    // Peripheral Wire Connections
    wire        uart_sout;
    wire        spi_out;
    wire [ 3:0] spi_cs;
    wire        spi_clk;
    wire        spi_in;

    // -------------------------------------------------------------------------
    // DUT: Coreless 1TOPS SoC
    // -------------------------------------------------------------------------
    riscv_soc_ahb_coreless #(
        .MEM_SIZE_BYTES(65536),
        .IRAM_BASE(32'h8000_0000),
        .IRAM_SIZE_BYTES(32768),
        .DRAM_BASE(32'h8001_0000),
        .DRAM_SIZE_BYTES(32768),
        .XLEN(32)
    ) dut (
        .clk(clk),
        .reset(reset),

        // AHB-Lite Master Test Port (from UVM Master VIP)
        .test_HADDR(ahb_vif.HADDR),
        .test_HWDATA(ahb_vif.HWDATA),
        .test_HWSTRB(ahb_vif.HWSTRB),
        .test_HWRITE(ahb_vif.HWRITE),
        .test_HTRANS(ahb_vif.HTRANS),
        .test_HSIZE(ahb_vif.HSIZE),
        .test_HBURST(ahb_vif.HBURST),
        .test_HPROT(ahb_vif.HPROT),
        .test_HMASTLOCK(ahb_vif.HMASTLOCK),
        .test_HRDATA(ahb_vif.HRDATA),
        .test_HREADY(ahb_vif.HREADY),
        .test_HRESP(ahb_vif.HRESP),

        // Boot Mode Pin Strap
        .boot_mode(1'b0),

        // GPIO
        .GPIOIN(gpio_vif.gpio_in),
        .GPIOOUT(gpio_vif.gpio_out),
        .GPIOEN(gpio_vif.gpio_en),

        // UART
        .UARTSin(1'b1),
        .UARTSout(uart_sout),

        // SPI
        .SPIIn(spi_in),
        .SPIOut(spi_out),
        .SPICS(spi_cs),
        .SPICLK(spi_clk),

        // Interrupt Outputs to IRQ VIP
        .MTimerInt(irq_vif.mtimer_int),
        .MSwInt(irq_vif.msw_int),
        .MExtInt(irq_vif.mext_int),
        .GPIOIntr(irq_vif.gpio_intr),
        .UARTIntr(irq_vif.uart_intr),
        .SPIIntr(irq_vif.spi_intr),

        // Telemetry
        .boot_mode_latched(),
        .remap_en(),
        .reset_vector(),
        .soft_core_rst_n()
    );

    // Feed GPIOIntr also to gpio_vif
    assign gpio_vif.gpio_intr = irq_vif.gpio_intr;
    assign irq_vif.sext_int   = 1'b0;
    assign irq_vif.sdc_intr   = 1'b0;

    // -------------------------------------------------------------------------
    // External SPI Flash Model
    // -------------------------------------------------------------------------
    spi_flash_model u_spi_flash (
        .sclk(spi_clk),
        .cs_n(spi_cs[0]),
        .mosi(spi_out),
        .miso(spi_in)
    );

    // -------------------------------------------------------------------------
    // SVA: Formal AHB Protocol Checker
    // -------------------------------------------------------------------------
    ahb_protocol_checker u_ahb_checker (
        .HCLK(clk),
        .HRESETn(rst_n),
        .HADDR(ahb_vif.HADDR),
        .HWDATA(ahb_vif.HWDATA),
        .HWSTRB(ahb_vif.HWSTRB),
        .HWRITE(ahb_vif.HWRITE),
        .HSIZE(ahb_vif.HSIZE),
        .HTRANS(ahb_vif.HTRANS),
        .HRDATA(ahb_vif.HRDATA),
        .HREADY(ahb_vif.HREADY),
        .HRESP(ahb_vif.HRESP),
        .HSEL_SLAVES(4'b0001)
    );

    // -------------------------------------------------------------------------
    // Testbench Registration and Start
    // -------------------------------------------------------------------------
    initial begin
        uvm_config_db#(virtual ahb_lite_if#(32, 32))::set(null, "uvm_test_top.env.ahb_ag*",  "vif", ahb_vif);
        uvm_config_db#(virtual gpio_if)::set(null,          "uvm_test_top.env.gpio_ag*", "vif", gpio_vif);
        uvm_config_db#(virtual irq_if)::set(null,          "uvm_test_top.env.irq_ag*",  "vif", irq_vif);

        uvm_config_db#(virtual ahb_lite_if#(32, 32))::set(null, "uvm_test_top.env", "ahb_vif",  ahb_vif);
        uvm_config_db#(virtual gpio_if)::set(null,          "uvm_test_top.env", "gpio_vif", gpio_vif);
        uvm_config_db#(virtual irq_if)::set(null,          "uvm_test_top.env", "irq_vif",  irq_vif);

        run_test();
    end

endmodule
