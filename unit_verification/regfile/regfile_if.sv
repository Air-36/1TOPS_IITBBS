interface regfile_if(input logic clk);

    logic wr_en;
    logic [4:0] wr_addr;
    logic [31:0] wr_data;
    logic [4:0] rd_addr1;
    logic [4:0] rd_addr2;
    logic [31:0] rd_data1;
    logic [31:0] rd_data2;
    logic [4:0] dbg_rd_addr;
    logic [31:0] dbg_rd_data;

    // Driver clocking block
    clocking drv_cb @(posedge clk);
        default input #1step output #1ns;
        output wr_en;
        output wr_addr;
        output wr_data;
        output rd_addr1;
        output rd_addr2;
        output dbg_rd_addr;
    endclocking

    // Monitor clocking block
    clocking mon_cb @(negedge clk);
        default input #1step;
        input wr_en;
        input wr_addr;
        input wr_data;
        input rd_addr1;
        input rd_addr2;
        input rd_data1;
        input rd_data2;
        input dbg_rd_addr;
        input dbg_rd_data;
    endclocking

endinterface
