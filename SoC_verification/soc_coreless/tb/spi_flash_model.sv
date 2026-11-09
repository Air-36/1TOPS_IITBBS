// =============================================================================
// Module: spi_flash_model
// Purpose: Behavioral Model of SPI Flash (e.g. W25Q series) for SoC Verification
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
        // Pre-populate first words with test pattern
        memory[0] = 8'h13;
        memory[1] = 8'h05;
        memory[2] = 8'ha0;
        memory[3] = 8'h02;
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
