// =============================================================================
// Module: riscv_soc_ahb_coreless
// Purpose: Coreless 1TOPS System-on-Chip DUT for AHB-Lite UVM Verification
//          Replaces CPU core & Debugger masters with an external AHB Master Port.
//          Retains all real bus fabric, address decoders, bridges, memories,
//          peripherals, and interrupt controllers.
// =============================================================================

`timescale 1ns/1ps

module riscv_soc_ahb_coreless #(
    parameter MEM_SIZE_BYTES  = 65536,
    parameter IRAM_BASE       = 32'h8000_0000,
    parameter IRAM_SIZE_BYTES = 32768,
    parameter DRAM_BASE       = 32'h8001_0000,
    parameter DRAM_SIZE_BYTES = 32768,
    parameter XLEN            = 32
)(
    input  logic              clk,
    input  logic              reset,

    // AMBA 3 AHB-Lite Master Test Port (Driven by UVM AHB Master VIP)
    input  logic [31:0]       test_HADDR,
    input  logic [31:0]       test_HWDATA,
    input  logic [ 3:0]       test_HWSTRB,
    input  logic              test_HWRITE,
    input  logic [ 1:0]       test_HTRANS,
    input  logic [ 2:0]       test_HSIZE,
    input  logic [ 2:0]       test_HBURST,
    input  logic [ 3:0]       test_HPROT,
    input  logic              test_HMASTLOCK,
    output logic [31:0]       test_HRDATA,
    output logic              test_HREADY,
    output logic              test_HRESP,

    // External Physical Pin Straps
    input  logic              boot_mode,

    // Peripheral I/O Pins
    input  logic [31:0]       GPIOIN,
    output logic [31:0]       GPIOOUT,
    output logic [31:0]       GPIOEN,
    input  logic              UARTSin,
    output logic              UARTSout,
    input  logic              SPIIn,
    output logic              SPIOut,
    output logic [ 3:0]       SPICS,
    output logic              SPICLK,

    // Interrupt Outputs to Testbench / Top Monitors
    output logic              MTimerInt,
    output logic              MSwInt,
    output logic              MExtInt,
    output logic              GPIOIntr,
    output logic              UARTIntr,
    output logic              SPIIntr,

    // System Control Telemetry
    output logic              boot_mode_latched,
    output logic              remap_en,
    output logic [31:0]       reset_vector,
    output logic              soft_core_rst_n
);

    wire HCLK    = clk;
    wire HRESETn = ~reset;

    // External AHB Slave / Accelerator Interface Wires (0x3000_0000 - 0x30FF_FFFF)
    wire        HSELEXT;
    wire [31:0] HRDATAEXT;
    wire        HREADYEXT;
    wire        HRESPEXT;

    // Core Debug AHB Slave Interface Wires (0x0B00_0000 - 0x0B00_0FFF)
    wire        HSELCOREDBG;
    wire [31:0] HRDATACOREDBG;
    wire        HREADYCOREDBG;
    wire        HRESPCOREDBG;

    // Bus HREADY Loopback
    wire HREADYOUT_uncore;
    assign test_HREADY = HREADYOUT_uncore;

    // -------------------------------------------------------------------------
    // 1. Uncore Subsystem Instantiation
    // -------------------------------------------------------------------------
    uncore #(
        .MEM_SIZE_BYTES(MEM_SIZE_BYTES),
        .IRAM_BASE(IRAM_BASE),
        .IRAM_SIZE_BYTES(IRAM_SIZE_BYTES),
        .DRAM_BASE(DRAM_BASE),
        .DRAM_SIZE_BYTES(DRAM_SIZE_BYTES),
        .XLEN(XLEN),
        .BOOTROM_SUPPORTED(1),
        .SYSCTRL_SUPPORTED(1),
        .SPI_SUPPORTED(1),
        .CLINT_SUPPORTED(1),
        .PLIC_SUPPORTED(1),
        .UART_SUPPORTED(1),
        .GPIO_SUPPORTED(1)
    ) u_uncore (
        .HCLK(HCLK),
        .HRESETn(HRESETn),
        .HADDR(test_HADDR),
        .HWDATA(test_HWDATA),
        .HWSTRB(test_HWSTRB),
        .HWRITE(test_HWRITE),
        .HTRANS(test_HTRANS),
        .HREADY(test_HREADY),
        .HRDATA(test_HRDATA),
        .HREADYOUT(HREADYOUT_uncore),
        .HRESP(test_HRESP),
        .HSELEXT(HSELEXT),
        .HRDATAEXT(HRDATAEXT),
        .HREADYEXT(HREADYEXT),
        .HRESPEXT(HRESPEXT),
        .HSELCOREDBG(HSELCOREDBG),
        .HRDATACOREDBG(HRDATACOREDBG),
        .HREADYCOREDBG(HREADYCOREDBG),
        .HRESPCOREDBG(HRESPCOREDBG),
        .MTimerInt(MTimerInt),
        .MSwInt(MSwInt),
        .MExtInt(MExtInt),
        .SExtInt(),
        .MTIME_CLINT(),
        .GPIOIN(GPIOIN),
        .GPIOOUT(GPIOOUT),
        .GPIOEN(GPIOEN),
        .UARTSin(UARTSin),
        .UARTSout(UARTSout),
        .SPIIn(SPIIn),
        .SPIOut(SPIOut),
        .SPICS(SPICS),
        .SPICLK(SPICLK),
        .SDCCmd(),
        .SDCCS(),
        .SDCCLK(),
        .reset_vector(reset_vector),
        .boot_mode_latched(boot_mode_latched),
        .remap_en(remap_en),
        .boot_mode_pin(boot_mode),
        .dbg_core_reset_i(1'b0),
        .soft_core_rst_n(soft_core_rst_n)
    );

    // Tap internal peripheral interrupts from uncore for observation
    assign GPIOIntr = u_uncore.GPIOIntr;
    assign UARTIntr = u_uncore.UARTIntr;
    assign SPIIntr  = u_uncore.SPIIntr;

    // -------------------------------------------------------------------------
    // 2. Dedicated Hardware Multiplier AHB Accelerator (0x3000_0000 - 0x30FF_FFFF)
    // -------------------------------------------------------------------------
    multiplier_ahb #(
        .XLEN(XLEN)
    ) u_multiplier (
        .clk(clk),
        .reset(reset),
        .HSEL(HSELEXT),
        .HADDR(test_HADDR),
        .HWDATA(test_HWDATA),
        .HWRITE(test_HWRITE),
        .HTRANS(test_HTRANS),
        .HREADY(test_HREADY),
        .HREADYOUT(HREADYEXT),
        .HRESP(HRESPEXT),
        .HRDATA(HRDATAEXT)
    );

    // -------------------------------------------------------------------------
    // 3. Core Debug AHB Slave (0x0B00_0000 - 0x0B00_0FFF)
    // -------------------------------------------------------------------------
    core_debug_ahb #(
        .DATA_WIDTH(32)
    ) u_core_dbg (
        .HCLK(HCLK),
        .HRESETn(HRESETn),
        .core_reset_i(1'b0),
        .HSEL(HSELCOREDBG),
        .HADDR(test_HADDR),
        .HWDATA(test_HWDATA),
        .HWRITE(test_HWRITE),
        .HTRANS(test_HTRANS),
        .HREADY(test_HREADY),
        .HREADYOUT(HREADYCOREDBG),
        .HRESP(HRESPCOREDBG),
        .HRDATA(HRDATACOREDBG),
        .dbg_rf_raddr(),
        .dbg_rf_rdata(32'd0),
        .PCF(32'h0),
        .PCD(32'h0),
        .PCE(32'h0),
        .PCM(32'h0),
        .PCW(32'h0),
        .InstrD(32'h0),
        .InstrM(32'h0),
        .StallFlags(5'd0),
        .FlushFlags(3'd0),
        .ExternalStall(1'b0),
        .InstrRetired(1'b0),
        .TrapM(1'b0),
        .mretM(1'b0),
        .TrapCauseM(32'h0),
        .TrapValM(32'h0),
        .mstatus(32'h0),
        .mcause(32'h0),
        .mtval(32'h0),
        .mepc(32'h0),
        .mtvec(32'h0),
        .mie(32'h0),
        .mip(32'h0),
        .mscratch(32'h0),
        .cycle_cnt(64'd0),
        .instret_cnt(64'd0),
        .auto_halt_trap_o(),
        .trap_latched_o(),
        .fault_flags_o(),
        .uart_clkdiv_i(16'd0),
        .uart_clkdiv_we_o(),
        .uart_clkdiv_val_o(),
        .ft_clkdiv_i(8'd0),
        .ft_clkdiv_we_o(),
        .ft_clkdiv_val_o(),
        .dbg_sel_i(1'b0)
    );

endmodule : riscv_soc_ahb_coreless
