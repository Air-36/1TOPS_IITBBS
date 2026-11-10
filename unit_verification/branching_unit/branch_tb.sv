module branch_tb;

    import uvm_pkg::*;
    `include "uvm_macros.svh"
    
    // Interface instance
    branch_if bif();

    // DUT instance
    branching_unit dut (
        .funct3 (bif.funct3),
        .Zero   (bif.Zero),
        .Less   (bif.Less),
        .LessU  (bif.LessU),
        .Branch (bif.Branch)
    );

    initial begin
        uvm_config_db #(virtual branch_if)::set(
            null,
            "*",
            "vif",
            bif
        );
        run_test("branch_test");
    end
endmodule
