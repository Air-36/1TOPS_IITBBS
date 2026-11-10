module alu_tb_top;

    import uvm_pkg::*;
    import alu_uvm_pkg::*;

    //clock
    bit clk = 0;

    always #5 clk = ~clk;

    // Interface instance
    alu_if alu_vif(clk);

    // DUT instance
    alu #(
        .WIDTH(32)
    ) dut (
        .a        (alu_vif.a),
        .b        (alu_vif.b),
        .alu_ctrl (alu_vif.alu_ctrl),
        .alu_out  (alu_vif.alu_out),
        .zero     (alu_vif.zero),
        .less     (alu_vif.less),
        .less_u   (alu_vif.less_u)
    );

    initial begin
        uvm_config_db#(virtual alu_if)::set(
            null,
            "*",
            "vif",
            alu_vif
        );

        run_test("alu_test");
    end
endmodule
