// =============================================================================
// Class: soc_full_bringup_test
// Purpose: Verifies bare-metal boot, memory march, multiplier & SysCtrl registers
// =============================================================================

`ifndef SOC_FULL_BRINGUP_TEST_SV
`define SOC_FULL_BRINGUP_TEST_SV

class soc_full_bringup_test extends soc_full_base_test;
    `uvm_component_utils(soc_full_bringup_test)

    function new(string name = "soc_full_bringup_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        `uvm_info(get_name(), "Starting Full SoC Bring-Up & Memory March Test...", UVM_LOW)

        env.cov.sample_boot(2'd2); // Direct IRAM execution

        // Wait for CPU to complete execution
        wait_for_completion(100000);

        `uvm_info(get_name(), "Completed Full SoC Bring-Up Test.", UVM_LOW)
        phase.drop_objection(this);
    endtask

endclass : soc_full_bringup_test

`endif

