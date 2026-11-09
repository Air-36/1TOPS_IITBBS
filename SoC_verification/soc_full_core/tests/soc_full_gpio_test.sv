// =============================================================================
// Class: soc_full_gpio_test
// Purpose: Full SoC GPIO Verification with Active VIP Stimulus & Monitoring
// =============================================================================

`ifndef SOC_FULL_GPIO_TEST_SV
`define SOC_FULL_GPIO_TEST_SV

class soc_full_gpio_test extends soc_full_base_test;
    `uvm_component_utils(soc_full_gpio_test)

    function new(string name = "soc_full_gpio_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_phase phase);
        virtual gpio_if vif;
        phase.raise_objection(this);
        `uvm_info(get_name(), "Starting Full SoC GPIO VIP Test...", UVM_LOW)

        if (!uvm_config_db#(virtual gpio_if)::get(this, "", "gpio_vif", vif)) begin
            `uvm_fatal(get_name(), "gpio_vif not found")
        end

        // Initial default input state
        vif.gpio_in <= 32'd0;

        // Step 1: Wait for CPU to drive pattern 0xA5A5 on lower 16 bits
        `uvm_info(get_name(), "Waiting for CPU to drive GPIO pattern 0x0000A5A5...", UVM_LOW)
        fork
            begin
                wait ((vif.gpio_out & 32'h0000FFFF) == 32'h0000A5A5);
                `uvm_info(get_name(), "CPU drove 0x0000A5A5! Injecting VIP stimulus 0x56780000...", UVM_LOW)
                repeat (10) @(posedge vif.clk);
                vif.gpio_in <= 32'h56780000;

                // Step 2: Wait for CPU to acknowledge with 0x00005A5A
                wait ((vif.gpio_out & 32'h0000FFFF) == 32'h00005A5A);
                `uvm_info(get_name(), "CPU acknowledged with 0x00005A5A! Injecting VIP stimulus 0x12340000...", UVM_LOW)
                repeat (10) @(posedge vif.clk);
                vif.gpio_in <= 32'h12340000;

                // Step 3: Wait for CPU final output 0x0000CAFE
                wait ((vif.gpio_out & 32'h0000FFFF) == 32'h0000CAFE);
                `uvm_info(get_name(), "CPU completed GPIO sequence with 0x0000CAFE!", UVM_LOW)
            end
            begin
                wait_for_completion(100000);
            end
        join_any

        `uvm_info(get_name(), "Completed Full SoC GPIO VIP Test.", UVM_LOW)
        phase.drop_objection(this);
    endtask

endclass : soc_full_gpio_test

`endif

