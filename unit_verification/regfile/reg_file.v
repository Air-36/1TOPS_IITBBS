module reg_file #(parameter DATA_WIDTH = 32) (
        input       clk,
        input       wr_en,
        input       [4:0] rd_addr1, rd_addr2, wr_addr,
        input       [DATA_WIDTH-1:0] wr_data,
        output      [DATA_WIDTH-1:0] rd_data1, rd_data2,

        // Auxiliary Debug Read Port (combinational, scan-friendly, non-intrusive)
        input       [4:0]            dbg_rd_addr,
        output      [DATA_WIDTH-1:0] dbg_rd_data
    );

    reg [DATA_WIDTH-1:0] reg_file_arr [0:31];

// // synthesis translate_off
// initial begin
//     reg_file_arr[0] = 0; // hardwired x0 - 0
// end
// // synthesis translate_on

// register file write logic (synchronous)
    // spyglass disable_block STARC-2.3.4.3 STARC05-2.3.4.3 AsyncResetOrSet Clock_check04 ClockEdgeinfo Ar_resetcross01
    // SMD: Flip-flop has neither async reset / Recommended edge of clock not used / Unsynchronized reset crossing to unreset storage
    // SJ: RISC-V architectural register file is an unreset array written on negedge clk; wr_en is cleanly suppressed during reset
    always @(negedge clk) begin
        if (wr_en) reg_file_arr[wr_addr] <= wr_data;
    end
    // spyglass enable_block STARC-2.3.4.3 STARC05-2.3.4.3 AsyncResetOrSet Clock_check04 ClockEdgeinfo Ar_resetcross01

// register file read logic (combinational)
    assign rd_data1 = ( rd_addr1 != 0 ) ? reg_file_arr[rd_addr1] : 0;
    assign rd_data2 = ( rd_addr2 != 0 ) ? reg_file_arr[rd_addr2] : 0;

// Debug read port
    assign dbg_rd_data = ( dbg_rd_addr != 0 ) ? reg_file_arr[dbg_rd_addr] : 0;

endmodule
