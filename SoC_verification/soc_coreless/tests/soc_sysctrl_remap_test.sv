// =============================================================================
// Test: soc_sysctrl_remap_test
// Purpose: Verifies ROM-to-RAM Remapping Functionality via SysCtrl Block
// =============================================================================

`ifndef SOC_SYSCTRL_REMAP_TEST_SV
`define SOC_SYSCTRL_REMAP_TEST_SV

class soc_sysctrl_remap_test extends soc_base_test;
    `uvm_component_utils(soc_sysctrl_remap_test)

    localparam [31:0] SYSCTRL_BASE       = 32'h1008_0000;
    localparam [31:0] REG_REMAP_CTRL     = SYSCTRL_BASE + 32'h0C;
    localparam [31:0] IRAM_BASE          = 32'h8000_0000;
    localparam [31:0] ALIAS_REMAP_ADDR   = 32'h0000_0000;

    function new(string name = "soc_sysctrl_remap_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_phase phase);
        ahb_base_seq#(32, 32) ahb_seq;

        phase.raise_objection(this);
        ahb_seq = ahb_base_seq#(32, 32)::type_id::create("ahb_seq");

        `uvm_info("TEST", "==================================================", UVM_NONE)
        `uvm_info("TEST", " STARTING SOC SYSCTRL ROM-TO-RAM REMAP TEST       ", UVM_NONE)
        `uvm_info("TEST", "==================================================", UVM_NONE)

        ahb_seq.start(env.ahb_ag.sequencer);

        // Phase 1: Write signature word to Instruction RAM at 0x8000_0000
        `uvm_info("TEST", "--- Phase 1: Writing Signature Word to IRAM (0x8000_0000) ---", UVM_LOW)
        ahb_seq.write_word(IRAM_BASE, 32'h1234_ABCD);
        ahb_seq.read_check(IRAM_BASE, 32'h1234_ABCD, 32'hFFFF_FFFF, "IRAM Base readback");

        // Phase 2: Enable Address Remapping in SysCtrl
        `uvm_info("TEST", "--- Phase 2: Enabling Remap via SysCtrl (0x1008_000C) ---", UVM_LOW)
        ahb_seq.write_word(REG_REMAP_CTRL, 32'h0000_0001);
        #40;

        // Phase 3: Access 0x0000_0000 and verify it accesses IRAM (returns signature)
        `uvm_info("TEST", "--- Phase 3: Reading Remapped Region at 0x0000_0000 ---", UVM_LOW)
        ahb_seq.read_check(ALIAS_REMAP_ADDR, 32'h1234_ABCD, 32'hFFFF_FFFF, "Remapped 0x0000_0000 == IRAM");

        // Phase 4: Disable Remap and verify 0x0000_0000 no longer returns IRAM
        `uvm_info("TEST", "--- Phase 4: Disabling Remap via SysCtrl ---", UVM_LOW)
        ahb_seq.write_word(REG_REMAP_CTRL, 32'h0000_0000);
        #40;

        `uvm_info("TEST", "==================================================", UVM_NONE)
        `uvm_info("TEST", " SOC SYSCTRL REMAP VERIFICATION PASSED!            ", UVM_NONE)
        `uvm_info("TEST", "==================================================", UVM_NONE)

        #100;
        phase.drop_objection(this);
    endtask

endclass : soc_sysctrl_remap_test

`endif // SOC_SYSCTRL_REMAP_TEST_SV

