// =============================================================================
// Test: soc_reset_test
// Purpose: Verifies peripheral reset values through the SoC AHB bus fabric
// =============================================================================

`ifndef SOC_RESET_TEST_SV
`define SOC_RESET_TEST_SV

class soc_reset_test extends soc_base_test;
    `uvm_component_utils(soc_reset_test)

    function new(string name = "soc_reset_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_phase phase);
        ahb_base_seq#(32, 32) ahb_seq;

        phase.raise_objection(this);
        ahb_seq = ahb_base_seq#(32, 32)::type_id::create("ahb_seq");

        `uvm_info("TEST", "==================================================", UVM_NONE)
        `uvm_info("TEST", " STARTING SOC RESET VALUES VERIFICATION TEST      ", UVM_NONE)
        `uvm_info("TEST", "==================================================", UVM_NONE)

        ahb_seq.start(env.ahb_ag.sequencer);

        // 1. SysCtrl Reset Values
        `uvm_info("TEST", "--- Checking SysCtrl Reset Values via AHB ---", UVM_LOW)
        ahb_seq.read_check(32'h1008_0018, 32'h1709_50C1, 32'hFFFF_FFFF, "SysCtrl SYS_ID (0x1008_0018)");
        ahb_seq.read_check(32'h1008_0004, 32'h0000_1000, 32'hFFFF_FFFF, "SysCtrl Reset Vector (0x1008_0004)");
        ahb_seq.read_check(32'h1008_000C, 32'h0000_0000, 32'h0000_0001, "SysCtrl Remap Control (0x1008_000C)");

        // 2. GPIO Reset Values
        `uvm_info("TEST", "--- Checking GPIO Reset Values via AHB ---", UVM_LOW)
        ahb_seq.read_check(32'h1006_0004, 32'h0, 32'hFFFF_FFFF, "GPIO Input Enable (0x1006_0004)");
        ahb_seq.read_check(32'h1006_0008, 32'h0, 32'hFFFF_FFFF, "GPIO Output Enable (0x1006_0008)");
        ahb_seq.read_check(32'h1006_000C, 32'h0, 32'hFFFF_FFFF, "GPIO Output Value (0x1006_000C)");

        // 3. Multiplier Accelerator Reset Values
        `uvm_info("TEST", "--- Checking Multiplier Reset Values via AHB ---", UVM_LOW)
        ahb_seq.read_check(32'h3000_0000, 32'h0, 32'hFFFF_FFFF, "Multiplier Operand A (0x3000_0000)");
        ahb_seq.read_check(32'h3000_0004, 32'h0, 32'hFFFF_FFFF, "Multiplier Operand B (0x3000_0004)");
        ahb_seq.read_check(32'h3000_0008, 32'h0, 32'hFFFF_FFFF, "Multiplier Product (0x3000_0008)");

        // 4. CLINT Reset Values
        `uvm_info("TEST", "--- Checking CLINT Reset Values via AHB ---", UVM_LOW)
        ahb_seq.read_check(32'h0200_0000, 32'h0, 32'h1, "CLINT MSIP (0x0200_0000)");

        // 5. Interrupt Lines Initial State
        if (env.irq_vif.mtimer_int !== 1'b0 || env.irq_vif.msw_int !== 1'b0 || env.irq_vif.mext_int !== 1'b0) begin
            `uvm_error("TEST", "One or more SoC interrupt lines asserted at reset!")
        end else begin
            `uvm_info("TEST", "All SoC interrupt lines (MTimerInt, MSwInt, MExtInt) are 0 at reset.", UVM_LOW)
        end

        `uvm_info("TEST", "==================================================", UVM_NONE)
        `uvm_info("TEST", " SOC RESET VALUES VERIFICATION PASSED!            ", UVM_NONE)
        `uvm_info("TEST", "==================================================", UVM_NONE)

        #100;
        phase.drop_objection(this);
    endtask

endclass : soc_reset_test

`endif // SOC_RESET_TEST_SV

