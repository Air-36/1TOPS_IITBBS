// =============================================================================
// Test: sysctrl_unit_test
// Purpose: UVM Test for System Control Block (SysCtrl)
// =============================================================================

`ifndef SYSCTRL_UNIT_TEST_SV
`define SYSCTRL_UNIT_TEST_SV

class sysctrl_unit_test extends uvm_test;
    `uvm_component_utils(sysctrl_unit_test)

    sysctrl_unit_env env;

    localparam [7:0] REG_RESET_CTRL  = 8'h00;
    localparam [7:0] REG_RESET_VEC   = 8'h04;
    localparam [7:0] REG_BOOT_STATUS = 8'h08;
    localparam [7:0] REG_REMAP_CTRL  = 8'h0C;
    localparam [7:0] REG_CLK_CTRL    = 8'h10;
    localparam [7:0] REG_SCRATCHPAD  = 8'h14;
    localparam [7:0] REG_SYS_ID      = 8'h18;

    localparam [31:0] SYS_ID_VAL     = 32'h1709_50C1;

    function new(string name = "sysctrl_unit_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = sysctrl_unit_env::type_id::create("env", this);
    endfunction

    virtual task run_phase(uvm_phase phase);
        apb_base_seq#(32, 32) apb_seq;

        phase.raise_objection(this);
        apb_seq = apb_base_seq#(32, 32)::type_id::create("apb_seq");

        `uvm_info("TEST", "==================================================", UVM_NONE)
        `uvm_info("TEST", " STARTING SYSCTRL IP UNIT TESTBENCH                ", UVM_NONE)
        `uvm_info("TEST", "==================================================", UVM_NONE)

        apb_seq.start(env.apb_ag.sequencer);

        // Phase 1: Read-Only System ID Check
        `uvm_info("TEST", "--- Phase 1: Checking Read-Only SYS_ID ---", UVM_LOW)
        apb_seq.read_check(REG_SYS_ID, SYS_ID_VAL, 32'hFFFF_FFFF, "SYS_ID");

        // Try writing to SYS_ID and verify it is RO
        apb_seq.write(REG_SYS_ID, 32'hDEAD_BEEF);
        apb_seq.read_check(REG_SYS_ID, SYS_ID_VAL, 32'hFFFF_FFFF, "SYS_ID should remain unchanged");

        // Phase 2: Scratchpad Read/Write
        `uvm_info("TEST", "--- Phase 2: Scratchpad Read/Write Test ---", UVM_LOW)
        apb_seq.write(REG_SCRATCHPAD, 32'hCAFE_BABE);
        apb_seq.read_check(REG_SCRATCHPAD, 32'hCAFE_BABE, 32'hFFFF_FFFF, "Scratchpad pattern 1");

        apb_seq.write(REG_SCRATCHPAD, 32'h1234_5678);
        apb_seq.read_check(REG_SCRATCHPAD, 32'h1234_5678, 32'hFFFF_FFFF, "Scratchpad pattern 2");

        // Phase 3: Programmable Reset Vector
        `uvm_info("TEST", "--- Phase 3: Programmable Reset Vector Test ---", UVM_LOW)
        apb_seq.read_check(REG_RESET_VEC, 32'h0000_1000, 32'hFFFF_FFFF, "Default Reset Vector");
        apb_seq.write(REG_RESET_VEC, 32'h8000_0000);
        apb_seq.read_check(REG_RESET_VEC, 32'h8000_0000, 32'hFFFF_FFFF, "Updated Reset Vector");

        // Phase 4: Remap Control
        `uvm_info("TEST", "--- Phase 4: ROM/RAM Remap Control Test ---", UVM_LOW)
        apb_seq.read_check(REG_REMAP_CTRL, 32'h0, 32'h1, "Default Remap Disabled");
        apb_seq.write(REG_REMAP_CTRL, 32'h1);
        apb_seq.read_check(REG_REMAP_CTRL, 32'h1, 32'h1, "Remap Enabled");

        // Phase 5: Clock Gating Mask
        `uvm_info("TEST", "--- Phase 5: Clock Gating Control Test ---", UVM_LOW)
        apb_seq.write(REG_CLK_CTRL, 32'h5A);
        apb_seq.read_check(REG_CLK_CTRL, 32'h5A, 32'hFF, "Clock Gate Mask");

        `uvm_info("TEST", "==================================================", UVM_NONE)
        `uvm_info("TEST", " SYSCTRL IP UNIT VERIFICATION PASSED SUCCESSFULLY!", UVM_NONE)
        `uvm_info("TEST", "==================================================", UVM_NONE)

        #100;
        phase.drop_objection(this);
    endtask

endclass : sysctrl_unit_test

`endif // SYSCTRL_UNIT_TEST_SV

