// =============================================================================
// Class: soc_full_suite_test
// Purpose: Comprehensive Full SoC Regression Test
// =============================================================================

`ifndef SOC_FULL_SUITE_TEST_SV
`define SOC_FULL_SUITE_TEST_SV

class soc_full_suite_test extends soc_full_base_test;
    `uvm_component_utils(soc_full_suite_test)

    function new(string name = "soc_full_suite_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_phase phase);
        virtual gpio_if vif;
        phase.raise_objection(this);
        `uvm_info(get_name(), "Starting Comprehensive Full SoC All-Peripheral Suite Test...", UVM_LOW)

        if (!uvm_config_db#(virtual gpio_if)::get(this, "", "gpio_vif", vif)) begin
            `uvm_fatal(get_name(), "gpio_vif not found")
        end

        fork
            begin
                // Inject PLIC GPIO edge once CPU arms PLIC
                wait ($root.tb_soc_full_top.plic_armed);
                `uvm_info(get_name(), "CPU armed PLIC! Injecting GPIO rising edge...", UVM_LOW)
                repeat (10) @(posedge vif.clk);
                vif.gpio_in[3] <= 1'b1;
                repeat (20) @(posedge vif.clk);
                vif.gpio_in[3] <= 1'b0;
            end
            begin
                wait_for_completion(150000);
            end
        join_any

        `uvm_info(get_name(), "Completed Comprehensive Full SoC Suite Test.", UVM_LOW)
        phase.drop_objection(this);
    endtask

endclass : soc_full_suite_test

`endif

