// =============================================================================
// Class: soc_full_clint_test
// Purpose: Full SoC CLINT Verification (Timer IRQ & Software IRQ)
// =============================================================================

`ifndef SOC_FULL_CLINT_TEST_SV
`define SOC_FULL_CLINT_TEST_SV

class soc_full_clint_test extends soc_full_base_test;
    `uvm_component_utils(soc_full_clint_test)

    function new(string name = "soc_full_clint_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        `uvm_info(get_name(), "Starting Full SoC CLINT Interrupt Test...", UVM_LOW)

        wait_for_completion(100000);

        `uvm_info(get_name(), "Completed Full SoC CLINT Test.", UVM_LOW)
        phase.drop_objection(this);
    endtask

endclass : soc_full_clint_test

`endif

