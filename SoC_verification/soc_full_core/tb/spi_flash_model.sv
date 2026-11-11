// =============================================================================
// Module: spi_flash_model
// Purpose: Behavioral Model of SPI Flash (W25Q series) for SoC Verification
//          Supports:
//          - Command 0x03 (Standard SPI Read with 24-bit address)
//          - Byte stream read with automatic address incrementation
//          - Preloaded bootloader image for Boot Mode 1 SPI Flash boot test
// =============================================================================

`timescale 1ns/1ps

module spi_flash_model (
    input  logic       sclk,
    input  logic       cs_n,
    input  logic       mosi,
    output logic       miso
);

    logic [7:0] memory [0:4095];
    logic [7:0] shift_in;
    logic [7:0] shift_out;
    logic [23:0] addr;
    int bit_cnt;

    typedef enum logic [1:0] {
        ST_CMD,
        ST_ADDR,
        ST_DATA
    } state_e;

    state_e state;
    logic [7:0] cmd;

    initial begin
        miso = 1'b0;
        state = ST_CMD;
        bit_cnt = 0;
        addr = 24'd0;
        shift_in = 8'd0;
        shift_out = 8'd0;

        // Initialize flash memory with 0
        for (int i = 0; i < 4096; i++) begin
            memory[i] = 8'h00;
        end

        // ---------------------------------------------------------------------
        // Pre-populate first 32 bytes (8 instructions) for SPI Boot Loader
        // ---------------------------------------------------------------------
        // 0x00: 0x02a00513 -> li a0, 42 (Bytes: 13 05 a0 02)
        memory[0]  = 8'h13;
        memory[1]  = 8'h05;
        memory[2]  = 8'ha0;
        memory[3]  = 8'h02;

        // 0x04: 0x100802b7 -> lui t0, 0x10080 (SYSCTRL base)
        memory[4]  = 8'hb7;
        memory[5]  = 8'h02;
        memory[6]  = 8'h08;
        memory[7]  = 8'h10;

        // 0x08: 0x00a2aa23 -> sw a0, 0x14(t0) (scratchpad = 42)
        memory[8]  = 8'h23;
        memory[9]  = 8'haa;
        memory[10] = 8'ha2;
        memory[11] = 8'h00;

        // 0x0C: 0x80018337 -> lui t1, 0x80018 (top of DRAM)
        memory[12] = 8'h37;
        memory[13] = 8'h83;
        memory[14] = 8'h01;
        memory[15] = 8'h80;

        // 0x10: 0x00100393 -> li t2, 1 (PASS signature)
        memory[16] = 8'h93;
        memory[17] = 8'h03;
        memory[18] = 8'h10;
        memory[19] = 8'h00;

        // 0x14: 0x00732e23 -> sw t2, -4(t1) (write 1 to 0x80017FFC)
        memory[20] = 8'h23;
        memory[21] = 8'h2e;
        memory[22] = 8'h73;
        memory[23] = 8'h00;

        // 0x18: 0x10500073 -> wfi
        memory[24] = 8'h73;
        memory[25] = 8'h00;
        memory[26] = 8'h50;
        memory[27] = 8'h10;

        // 0x1C: 0x0000006f -> j 0x1C (infinite sleep loop)
        memory[28] = 8'h6f;
        memory[29] = 8'h00;
        memory[30] = 8'h00;
        memory[31] = 8'h00;
    end

    always @(negedge cs_n) begin
        state   <= ST_CMD;
        bit_cnt <= 0;
        addr    <= 24'd0;
        miso    <= 1'b0;
    end

    always @(posedge sclk) begin
        if (!cs_n) begin
            shift_in <= {shift_in[6:0], mosi};
            bit_cnt  <= bit_cnt + 1;

            if (state == ST_CMD) begin
                if (bit_cnt == 7) begin
                    cmd     <= {shift_in[6:0], mosi};
                    state   <= ST_ADDR;
                    bit_cnt <= 0;
                    addr    <= 24'd0;
                end
            end else if (state == ST_ADDR) begin
                addr <= {addr[22:0], mosi};
                if (bit_cnt == 23) begin
                    state     <= ST_DATA;
                    bit_cnt   <= 0;
                    shift_out <= memory[{addr[22:0], mosi} % 4096];
                end
            end else if (state == ST_DATA) begin
                if (bit_cnt % 8 == 7) begin
                    addr      <= (addr + 1) % 4096;
                    shift_out <= memory[(addr + 1) % 4096];
                end
            end
        end
    end

    always @(negedge sclk) begin
        if (!cs_n && state == ST_DATA) begin
            miso <= shift_out[7];
            shift_out <= {shift_out[6:0], 1'b0};
        end else begin
            miso <= 1'b0;
        end
    end

endmodule

