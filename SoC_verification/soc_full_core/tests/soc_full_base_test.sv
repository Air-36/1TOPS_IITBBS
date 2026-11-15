// =============================================================================
// Class: soc_full_base_test
// Purpose: Base UVM Test for Full 1TOPS RISC-V SoC Verification
// =============================================================================

`ifndef SOC_FULL_BASE_TEST_SV
`define SOC_FULL_BASE_TEST_SV

class soc_full_base_test extends uvm_test;
    `uvm_component_utils(soc_full_base_test)

    soc_full_env       env;
    virtual soc_ctrl_if ctrl_vif;

    function new(string name = "soc_full_base_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = soc_full_env::type_id::create("env", this);
        if (!uvm_config_db#(virtual soc_ctrl_if)::get(this, "", "ctrl_vif", ctrl_vif)) begin
            `uvm_fatal(get_name(), "ctrl_vif not found in uvm_config_db")
        end
    endfunction

    // Helper task to wait for CPU PASS / FAIL or timeout
    virtual task wait_for_completion(int max_cycles = 150000);
        int cycle_count = 0;
        forever begin
            @(posedge ctrl_vif.clk);
            cycle_count++;

            if (ctrl_vif.test_passed) begin
                `uvm_info(get_name(), "Test Execution PASSED! Mailbox signature confirmed.", UVM_LOW)
                repeat (20) @(posedge ctrl_vif.clk);
                return;
            end

            if (ctrl_vif.test_failed) begin
                `uvm_error(get_name(), $sformatf("Test Execution FAILED! Error Code: 0x%08h", 
                           ctrl_vif.error_code))
                return;
            end

            if (cycle_count >= max_cycles) begin
                `uvm_error(get_name(), $sformatf("TIMEOUT! Simulation limit reached (%0d cycles) without completion.", max_cycles))
                return;
            end
        end
    endtask

endclass : soc_full_base_test

`endif

