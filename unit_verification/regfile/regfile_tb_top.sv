module regfile_tb_top;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    // Clock
    bit clk = 0;
    always #5 clk = ~clk;

    // Interface
    regfile_if vif(clk);

    // DUT
    reg_file #(
        .DATA_WIDTH(32)
    ) dut (
        .clk        (clk),

        .wr_en      (vif.wr_en),
        .wr_addr    (vif.wr_addr),
        .wr_data    (vif.wr_data),

        .rd_addr1   (vif.rd_addr1),
        .rd_addr2   (vif.rd_addr2),
        .rd_data1   (vif.rd_data1),
        .rd_data2   (vif.rd_data2),

        .dbg_rd_addr(vif.dbg_rd_addr),
        .dbg_rd_data(vif.dbg_rd_data)
    );


    initial begin
        uvm_config_db #(virtual regfile_if)::set(
            null,
            "*",
            "vif",
            vif
        );
        run_test("regfile_test");
    end
endmodule
