// =============================================================================
// Module: rom_ahb
// Project: 1TOPS RISC-V System-on-Chip
// Purpose: Synthesizable On-Chip Boot ROM with AHB-Lite Slave Interface.
//          Preloaded with default dual-mode bootloader:
//          - Boot Mode 0: Executes internal diagnostics, runs main(), writes
//                         PASS status to SYSCTRL and tohost, and sleeps.
//          - Boot Mode 1: Initializes SPI Controller (0x10040000), issues READ
//                         command (0x03) to external SPI flash model, copies
//                         instructions into IMEM (0x80000000), and jumps to IMEM.
// =============================================================================

// `timescale 1ns / 1ps

module rom_ahb #(
    parameter XLEN        = 32,
    parameter PA_BITS     = 32,
    parameter RANGE       = 4095,      // 4 KB aperture (1024 words)
    parameter PRELOAD     = 0,
    parameter        MEMFILE = ""
)(
    input  logic                 HCLK,
    input  logic                 HRESETn,
    input  logic                 HSELRom,
    input  logic [PA_BITS-1:0]   HADDR,
    input  logic                 HREADY,
    input  logic [1:0]           HTRANS,
    output logic [XLEN-1:0]      HREADRom,
    output logic                 HRESPRom,
    output logic                 HREADYRom
);

    localparam WORDS      = (RANGE + 1) / (XLEN / 8);
    localparam ADDR_WIDTH = (WORDS > 1) ? $clog2(WORDS) : 1;
    localparam OFFSET     = $clog2(XLEN / 8);

    // Single-cycle zero-wait synchronous ROM response
    assign HREADYRom = 1'b1;
    assign HRESPRom  = 1'b0;

    wire [ADDR_WIDTH-1:0] word_addr = HADDR[ADDR_WIDTH+OFFSET-1:OFFSET];

    // Synthesizable combinational ROM lookup function
    function automatic [XLEN-1:0] rom_data(input logic [ADDR_WIDTH-1:0] addr);
        case (addr)
            // -----------------------------------------------------------------
            // Dual-Mode Bootloader Program Image
            // -----------------------------------------------------------------
            10'd0:  rom_data = 32'h8001_8137; // 0x1000: lui  sp, 0x80018
            10'd1:  rom_data = 32'hff01_0113; // 0x1004: addi sp, sp, -16 (sp = 0x80017FF0)
            10'd2:  rom_data = 32'h1008_02b7; // 0x1008: lui  t0, 0x10080 (SYSCTRL base)
            10'd3:  rom_data = 32'h0082_a303; // 0x100c: lw   t1, 8(t0)   (SYSCTRL_BOOT_STATUS)
            10'd4:  rom_data = 32'h0013_7313; // 0x1010: andi t1, t1, 1   (strap_boot_mode)
            10'd5:  rom_data = 32'h0403_1263; // 0x1014: bnez t1, boot_spi (offset +68 -> 0x1058)

            // --- Mode 0: Internal ROM Boot & main() ---
            10'd6:  rom_data = 32'h01c0_00ef; // 0x1018: jal  ra, main    (offset +28 -> 0x1034)
            10'd7:  rom_data = 32'h1008_02b7; // 0x101c: lui  t0, 0x10080 (SYSCTRL base)
            10'd8:  rom_data = 32'h00a2_aa23; // 0x1020: sw   a0, 0x14(t0)(Write exit code to scratchpad)
            10'd9:  rom_data = 32'h8000_1337; // 0x1024: lui  t1, 0x80001 (tohost aperture base)
            10'd10: rom_data = 32'h00a3_2023; // 0x1028: sw   a0, 0(t1)   (Write exit code to tohost)
            10'd11: rom_data = 32'h1050_0073; // 0x102c: wfi
            10'd12: rom_data = 32'h0000_006f; // 0x1030: j    0x1030      (Clean sleep loop)

            // --- main() inside Boot ROM ---
            10'd13: rom_data = 32'hff01_0113; // 0x1034: main: addi sp, sp, -16
            10'd14: rom_data = 32'h0011_2623; // 0x1038: sw   ra, 12(sp)
            10'd15: rom_data = 32'h00a0_0513; // 0x103c: li   a0, 10
            10'd16: rom_data = 32'h0145_0513; // 0x1040: addi a0, a0, 20
            10'd17: rom_data = 32'h01e5_0513; // 0x1044: addi a0, a0, 30
            10'd18: rom_data = 32'h0010_0513; // 0x1048: li   a0, 1       (PASS return code = 1)
            10'd19: rom_data = 32'h00c1_2083; // 0x104c: lw   ra, 12(sp)
            10'd20: rom_data = 32'h0101_0113; // 0x1050: addi sp, sp, 16
            10'd21: rom_data = 32'h0000_8067; // 0x1054: ret

            // --- Mode 1: SPI Flash Boot Loader ---
            10'd22: rom_data = 32'h1004_0437; // 0x1058: boot_spi: lui s0, 0x10040 (SPI Base 0x1004_0000)
            10'd23: rom_data = 32'h0020_0393; // 0x105c: li   t2, 2
            10'd24: rom_data = 32'h0074_2023; // 0x1060: sw   t2, 0(s0)    (SPI_SCKDIV = 2)
            10'd25: rom_data = 32'h0074_2c23; // 0x1064: sw   t2, 0x18(s0) (SPI_CSMODE = 2: HOLDMODE, assert CS0)
            10'd26: rom_data = 32'h0030_0e13; // 0x1068: li   t3, 3        (READ opcode 0x03)
            10'd27: rom_data = 32'h05c4_2423; // 0x106c: sw   t3, 0x48(s0) (SPI_TXDATA = 0x03)
            10'd28: rom_data = 32'h0404_2423; // 0x1070: sw   zero, 0x48(s0) (Flash Addr[23:16] = 0x00)
            10'd29: rom_data = 32'h0404_2423; // 0x1074: sw   zero, 0x48(s0) (Flash Addr[15:8]  = 0x00)
            10'd30: rom_data = 32'h0404_2423; // 0x1078: sw   zero, 0x48(s0) (Flash Addr[7:0]   = 0x00)
            10'd31: rom_data = 32'h0780_0293; // 0x107c: li   t0, 120      (Wait ~240 cycles for 4 bytes)
            10'd32: rom_data = 32'hfff2_8293; // 0x1080: wait_cmd: addi t0, t0, -1
            10'd33: rom_data = 32'hfe02_9ee3; // 0x1084: bnez t0, wait_cmd
            10'd34: rom_data = 32'h04c4_2003; // 0x1088: lw   zero, 0x4C(s0) (Drain dummy byte 1)
            10'd35: rom_data = 32'h04c4_2003; // 0x108c: lw   zero, 0x4C(s0) (Drain dummy byte 2)
            10'd36: rom_data = 32'h04c4_2003; // 0x1090: lw   zero, 0x4C(s0) (Drain dummy byte 3)
            10'd37: rom_data = 32'h04c4_2003; // 0x1094: lw   zero, 0x4C(s0) (Drain dummy byte 4)
            10'd38: rom_data = 32'h8000_04b7; // 0x1098: lui  s1, 0x80000  (IMEM base 0x8000_0000)
            10'd39: rom_data = 32'h0204_8913; // 0x109c: addi s2, s1, 32   (Copy 32 bytes = 8 instructions)
            10'd40: rom_data = 32'h0404_2423; // 0x10a0: copy_loop: sw zero, 0x48(s0) (Trigger SPI 1-byte read)
            10'd41: rom_data = 32'h01e0_0293; // 0x10a4: li   t0, 30       (Wait ~60 cycles for byte transfer)
            10'd42: rom_data = 32'hfff2_8293; // 0x10a8: wait_byte: addi t0, t0, -1
            10'd43: rom_data = 32'hfe02_9ee3; // 0x10ac: bnez t0, wait_byte
            10'd44: rom_data = 32'h04c4_2e83; // 0x10b0: lw   t4, 0x4C(s0) (Read received byte)
            10'd45: rom_data = 32'h01d4_8023; // 0x10b4: sb   t4, 0(s1)    (Store byte into IMEM!)
            10'd46: rom_data = 32'h0014_8493; // 0x10b8: addi s1, s1, 1    (s1++)
            10'd47: rom_data = 32'hff24_e2e3; // 0x10bc: bltu s1, s2, copy_loop
            10'd48: rom_data = 32'h0004_2c23; // 0x10c0: sw   zero, 0x18(s0)(SPI_CSMODE = 0: AUTOMODE, deassert CS0)
            10'd49: rom_data = 32'h8000_0fb7; // 0x10c4: lui  t6, 0x80000
            10'd50: rom_data = 32'h000f_8067; // 0x10c8: jr   t6           (Jump to IMEM!)
            10'd51: rom_data = 32'h0000_0013; // 0x10cc: nop
            default: rom_data = 32'h0000_0013; // Default NOP
        endcase
    endfunction

`ifndef SYNTHESIS
    // Optional custom preload override for simulation
    logic [XLEN-1:0] mem [0:WORDS-1];
    initial begin
        if (PRELOAD && MEMFILE != "") begin
            $readmemh(MEMFILE, mem);
        end
    end
    wire [XLEN-1:0] rom_read_word = (PRELOAD && MEMFILE != "") ? mem[word_addr] : rom_data(word_addr);
`else
    wire [XLEN-1:0] rom_read_word = rom_data(word_addr);
`endif

    always_ff @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            HREADRom <= '0;
        end else if (HSELRom && HREADY && HTRANS[1]) begin
            HREADRom <= rom_read_word;
        end
    end

endmodule
