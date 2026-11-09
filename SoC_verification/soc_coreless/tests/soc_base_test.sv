// =============================================================================
// Test: soc_base_test
// Purpose: Base UVM test class for Coreless SoC Verification
// =============================================================================

`ifndef SOC_BASE_TEST_SV
`define SOC_BASE_TEST_SV

class soc_base_test extends uvm_test;
    `uvm_component_utils(soc_base_test)

    soc_coreless_env env;

    function new(string name = "soc_base_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = soc_coreless_env::type_id::create("env", this);
    endfunction

    virtual task run_phase(uvm_phase phase);
        // Base run phase (overridden by child tests)
    endtask

endclass : soc_base_test

`endif // SOC_BASE_TEST_SV

