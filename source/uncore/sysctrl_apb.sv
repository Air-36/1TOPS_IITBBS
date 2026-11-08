// =============================================================================
// Module: sysctrl_apb
// Project: 1TOPS RISC-V System-on-Chip
// Purpose: System Control Block with APB Slave Interface:
//          1. Synchronous Reset Control (POR, External, Software, Debugger)
//          2. Boot Mode Pin Strap Sampling & Latching
//          3. Programmable Reset Vector & ROM Address Remap Control
//          4. Peripheral Clock Gating & Power Management
//          5. System Identification & Diagnostics Scratchpad
// =============================================================================

// `timescale 1ns / 1ps

module sysctrl_apb #(
    parameter XLEN = 32
)(
    // APB Bus Interface
    input  logic                 PCLK,
    input  logic                 PRESETn,
    input  logic                 PSEL,
    input  logic [7:0]           PADDR,
    input  logic [XLEN-1:0]      PWDATA,
    input  logic [XLEN/8-1:0]    PSTRB,
    input  logic                 PWRITE,
    input  logic                 PENABLE,
    output logic                 PREADY,
    output logic [XLEN-1:0]      PRDATA,

    // External Physical Pin Straps
    input  logic                 boot_mode_pin,

    // External Reset & Debugger Hooks
    input  logic                 dbg_core_reset_i,

    // Control Outputs to SoC Fabric & Core
    output logic                 soft_core_rst_n_o,
    output logic                 soft_periph_rst_n_o,
    output logic                 boot_mode_latched_o,
    output logic                 boot_mode_live_o,
    output logic                 remap_en_o,
    output logic [31:0]          reset_vector_o,
    output logic [7:0]           clk_gate_mask_o
);

    // =========================================================================
    // Register Map Offsets
    // =========================================================================
    localparam [7:0] REG_RESET_CTRL  = 8'h00; // [0] Soft Core Reset, [1] Soft Periph Reset, [4] POR, [5] DBG
    localparam [7:0] REG_RESET_VEC   = 8'h04; // [31:0] Programmable Reset Vector (Default: 0x0000_1000)
    localparam [7:0] REG_BOOT_STATUS = 8'h08; // [0] Latched Strap, [1] Live Pin Level
    localparam [7:0] REG_REMAP_CTRL  = 8'h0C; // [0] ROM/RAM Remap Enable
    localparam [7:0] REG_CLK_CTRL    = 8'h10; // [7:0] Clock Gating Enables
    localparam [7:0] REG_SCRATCHPAD  = 8'h14; // [31:0] General Purpose R/W Scratchpad
    localparam [7:0] REG_SYS_ID      = 8'h18; // [31:0] Read-Only SoC Identification Word

    localparam [31:0] SYS_ID_VAL     = 32'h1709_50C1; // "1TOPS SOC 1"

    // =========================================================================
    // 1. Reset Conditioning & Strap Sampling Circuit
    // =========================================================================
    // 2-stage synchronizer and 4-bit hold counter to guarantee clean,
    // glitch-free de-assertion of the internal system reset.
    logic [1:0] rst_sync;
    logic [3:0] rst_hold_cnt;
    logic       internal_rst_n;

    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            rst_sync       <= 2'b00;
            rst_hold_cnt   <= 4'd0;
            internal_rst_n <= 1'b0;
        end else begin
            rst_sync <= {rst_sync[0], 1'b1};
            if (rst_sync[1]) begin
                if (rst_hold_cnt < 4'd15) begin
                    rst_hold_cnt   <= rst_hold_cnt + 1'b1;
                    internal_rst_n <= 1'b0;
                end else begin
                    internal_rst_n <= 1'b1;
                end
            end
        end
    end

    // Boot Strap Latch:
    // Tracks the external pin while in reset; latches and freezes on the rising
    // edge of internal_rst_n, ensuring rock-solid stability during active execution.
    logic strap_boot_mode_latched;

    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            strap_boot_mode_latched <= 1'b0;
        end else if (!internal_rst_n) begin
            strap_boot_mode_latched <= boot_mode_pin;
        end
    end

    assign boot_mode_latched_o = strap_boot_mode_latched;
    assign boot_mode_live_o    = boot_mode_pin;

    // Latch reset cause indicators
    logic por_occurred;
    logic dbg_reset_occurred;

    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            por_occurred       <= 1'b1;
            dbg_reset_occurred <= 1'b0;
        end else begin
            if (dbg_core_reset_i) begin
                dbg_reset_occurred <= 1'b1;
            end else if (PSEL && PENABLE && PWRITE && (PADDR[7:0] == REG_RESET_CTRL) && PSTRB[0] && PWDATA[5]) begin
                dbg_reset_occurred <= 1'b0; // Write 1 to clear DBG reset flag
            end

            if (PSEL && PENABLE && PWRITE && (PADDR[7:0] == REG_RESET_CTRL) && PSTRB[0] && PWDATA[4]) begin
                por_occurred <= 1'b0; // Write 1 to clear POR flag
            end
        end
    end

    // =========================================================================
    // 2. Control & Configuration Registers
    // =========================================================================
    logic        reg_soft_core_rst_n;
    logic        reg_soft_periph_rst_n;
    logic [31:0] reg_reset_vector;
    logic        reg_remap_en;
    logic [7:0]  reg_clk_gate_mask;
    logic [31:0] reg_scratchpad;

    // APB Write Handling
    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            reg_soft_core_rst_n   <= 1'b1;              // Normal running
            reg_soft_periph_rst_n <= 1'b1;              // Normal running
            reg_reset_vector      <= 32'h0000_1000;     // Default: Boot ROM base
            reg_remap_en          <= 1'b0;              // Default: Normal memory map
            reg_clk_gate_mask     <= 8'hFF;             // Default: All peripheral clocks enabled
            reg_scratchpad        <= 32'h0000_0000;
        end else if (PSEL && PENABLE && PWRITE) begin
            case (PADDR[7:0])
                REG_RESET_CTRL: begin
                    if (PSTRB[0]) begin
                        reg_soft_core_rst_n   <= PWDATA[0];
                        reg_soft_periph_rst_n <= PWDATA[1];
                    end
                end

                REG_RESET_VEC: begin
                    if (PSTRB[0]) reg_reset_vector[ 7: 0] <= PWDATA[ 7: 0];
                    if (PSTRB[1]) reg_reset_vector[15: 8] <= PWDATA[15: 8];
                    if (PSTRB[2]) reg_reset_vector[23:16] <= PWDATA[23:16];
                    if (PSTRB[3]) reg_reset_vector[31:24] <= PWDATA[31:24];
                end

                REG_REMAP_CTRL: begin
                    if (PSTRB[0]) reg_remap_en <= PWDATA[0];
                end

                REG_CLK_CTRL: begin
                    if (PSTRB[0]) reg_clk_gate_mask <= PWDATA[7:0];
                end

                REG_SCRATCHPAD: begin
                    if (PSTRB[0]) reg_scratchpad[ 7: 0] <= PWDATA[ 7: 0];
                    if (PSTRB[1]) reg_scratchpad[15: 8] <= PWDATA[15: 8];
                    if (PSTRB[2]) reg_scratchpad[23:16] <= PWDATA[23:16];
                    if (PSTRB[3]) reg_scratchpad[31:24] <= PWDATA[31:24];
                end

                default: begin end
            endcase
        end
    end

    // Register Outputs
    assign soft_core_rst_n_o   = reg_soft_core_rst_n;
    assign soft_periph_rst_n_o = reg_soft_periph_rst_n;
    assign reset_vector_o      = reg_reset_vector;
    assign remap_en_o          = reg_remap_en;
    assign clk_gate_mask_o     = reg_clk_gate_mask;

    // =========================================================================
    // 3. APB Read Multiplexer
    // =========================================================================
    assign PREADY = 1'b1; // Zero-wait state single cycle peripheral response

    always_comb begin
        PRDATA = '0;
        if (PSEL) begin
            case (PADDR[7:0])
                REG_RESET_CTRL: begin
                    PRDATA = {26'd0, dbg_reset_occurred, por_occurred, 2'b00,
                              reg_soft_periph_rst_n, reg_soft_core_rst_n};
                end

                REG_RESET_VEC: begin
                    PRDATA = reg_reset_vector;
                end

                REG_BOOT_STATUS: begin
                    PRDATA = {30'd0, boot_mode_pin, strap_boot_mode_latched};
                end

                REG_REMAP_CTRL: begin
                    PRDATA = {31'd0, reg_remap_en};
                end

                REG_CLK_CTRL: begin
                    PRDATA = {24'd0, reg_clk_gate_mask};
                end

                REG_SCRATCHPAD: begin
                    PRDATA = reg_scratchpad;
                end

                REG_SYS_ID: begin
                    PRDATA = SYS_ID_VAL;
                end

                default: begin
                    PRDATA = 32'hDEAD_BEEF;
                end
            endcase
        end
    end

endmodule

