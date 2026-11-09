// =============================================================================
// Test: soc_ahb_single_rw_test
// Purpose: Single Read/Write transactions to SRAM and Peripheral Registers via AHB
// =============================================================================

`ifndef SOC_AHB_SINGLE_RW_TEST_SV
`define SOC_AHB_SINGLE_RW_TEST_SV

class soc_ahb_single_rw_test extends soc_base_test;
    `uvm_component_utils(soc_ahb_single_rw_test)

    function new(string name = "soc_ahb_single_rw_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_phase phase);
        ahb_base_seq#(32, 32) ahb_seq;

        phase.raise_objection(this);
        ahb_seq = ahb_base_seq#(32, 32)::type_id::create("ahb_seq");

        `uvm_info("TEST", "==================================================", UVM_NONE)
        `uvm_info("TEST", " STARTING AHB SINGLE READ/WRITE TEST               ", UVM_NONE)
        `uvm_info("TEST", "==================================================", UVM_NONE)

        ahb_seq.start(env.ahb_ag.sequencer);

        // 1. Data RAM Access (0x8001_0000)
        `uvm_info("TEST", "--- Testing Data RAM R/W at 0x8001_0000 ---", UVM_LOW)
        ahb_seq.write_word(32'h8001_0000, 32'hDEAD_BEEF);
        ahb_seq.read_check(32'h8001_0000, 32'hDEAD_BEEF, 32'hFFFF_FFFF, "DRAM word 0");

        ahb_seq.write_word(32'h8001_0004, 32'h1234_5678);
        ahb_seq.read_check(32'h8001_0004, 32'h1234_5678, 32'hFFFF_FFFF, "DRAM word 1");

        // 2. Instruction RAM Access (0x8000_0000)
        `uvm_info("TEST", "--- Testing Instruction RAM R/W at 0x8000_0000 ---", UVM_LOW)
        ahb_seq.write_word(32'h8000_0000, 32'hA5A5_5A5A);
        ahb_seq.read_check(32'h8000_0000, 32'hA5A5_5A5A, 32'hFFFF_FFFF, "IRAM word 0");

        // 3. SysCtrl Scratchpad (0x1008_0014)
        `uvm_info("TEST", "--- Testing SysCtrl Scratchpad R/W at 0x1008_0014 ---", UVM_LOW)
        ahb_seq.write_word(32'h1008_0014, 32'hFEED_F00D);
        ahb_seq.read_check(32'h1008_0014, 32'hFEED_F00D, 32'hFFFF_FFFF, "SysCtrl Scratchpad");

        // 4. Hardware Multiplier (0x3000_0000)
        `uvm_info("TEST", "--- Testing Hardware Multiplier Accelerator at 0x3000_0000 ---", UVM_LOW)
        ahb_seq.write_word(32'h3000_0000, 32'd12);
        ahb_seq.write_word(32'h3000_0004, 32'd8);
        ahb_seq.read_check(32'h3000_0008, 32'd96, 32'hFFFF_FFFF, "Multiplier Product (12 * 8 = 96)");

        `uvm_info("TEST", "==================================================", UVM_NONE)
        `uvm_info("TEST", " AHB SINGLE READ/WRITE TEST PASSED SUCCESSFULLY!   ", UVM_NONE)
        `uvm_info("TEST", "==================================================", UVM_NONE)

        #100;
        phase.drop_objection(this);
    endtask

endclass : soc_ahb_single_rw_test

`endif // SOC_AHB_SINGLE_RW_TEST_SV

