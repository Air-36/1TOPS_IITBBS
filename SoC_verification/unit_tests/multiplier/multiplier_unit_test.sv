// =============================================================================
// Test: multiplier_unit_test
// Purpose: UVM Test for Hardware Multiplier AHB Slave Accelerator
// =============================================================================

`ifndef MULTIPLIER_UNIT_TEST_SV
`define MULTIPLIER_UNIT_TEST_SV

class multiplier_unit_test extends uvm_test;
    `uvm_component_utils(multiplier_unit_test)

    multiplier_unit_env env;

    localparam [31:0] REG_OP_A    = 32'h00;
    localparam [31:0] REG_OP_B    = 32'h04;
    localparam [31:0] REG_PRODUCT = 32'h08;

    function new(string name = "multiplier_unit_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = multiplier_unit_env::type_id::create("env", this);
    endfunction

    virtual task run_phase(uvm_phase phase);
        ahb_base_seq#(32, 32) ahb_seq;

        phase.raise_objection(this);
        ahb_seq = ahb_base_seq#(32, 32)::type_id::create("ahb_seq");

        `uvm_info("TEST", "==================================================", UVM_NONE)
        `uvm_info("TEST", " STARTING MULTIPLIER AHB UNIT TESTBENCH            ", UVM_NONE)
        `uvm_info("TEST", "==================================================", UVM_NONE)

        ahb_seq.start(env.ahb_ag.sequencer);

        // Phase 1: Reset Values
        `uvm_info("TEST", "--- Phase 1: Checking Reset Values ---", UVM_LOW)
        ahb_seq.read_check(REG_OP_A,    32'd0, 32'hFFFF_FFFF, "Reset Operand A");
        ahb_seq.read_check(REG_OP_B,    32'd0, 32'hFFFF_FFFF, "Reset Operand B");
        ahb_seq.read_check(REG_PRODUCT, 32'd0, 32'hFFFF_FFFF, "Reset Product Output");

        // Phase 2: Directed Multiplication Cases
        `uvm_info("TEST", "--- Phase 2: Directed Multiplications ---", UVM_LOW)
        test_mult(ahb_seq, 32'd7, 32'd6, 32'd42);
        test_mult(ahb_seq, 32'd100, 32'd250, 32'd25000);
        test_mult(ahb_seq, 32'd1000, 32'd0, 32'd0);
        test_mult(ahb_seq, 32'h0000_FFFF, 32'h0000_0002, 32'h0001_FFFE);

        // Phase 3: Random Tests
        `uvm_info("TEST", "--- Phase 3: Random Multiplications ---", UVM_LOW)
        for (int i = 0; i < 20; i++) begin
            bit [31:0] a = $urandom_range(0, 10000);
            bit [31:0] b = $urandom_range(0, 10000);
            test_mult(ahb_seq, a, b, a * b);
        end

        `uvm_info("TEST", "==================================================", UVM_NONE)
        `uvm_info("TEST", " MULTIPLIER AHB VERIFICATION PASSED SUCCESSFULLY! ", UVM_NONE)
        `uvm_info("TEST", "==================================================", UVM_NONE)

        #100;
        phase.drop_objection(this);
    endtask

    virtual task test_mult(ahb_base_seq#(32, 32) seq, bit [31:0] a, bit [31:0] b, bit [31:0] exp_prod);
        seq.write_word(REG_OP_A, a);
        seq.write_word(REG_OP_B, b);
        seq.read_check(REG_PRODUCT, exp_prod, 32'hFFFF_FFFF, $sformatf("Multiply %0d * %0d", a, b));
    endtask

endclass : multiplier_unit_test

`endif // MULTIPLIER_UNIT_TEST_SV

