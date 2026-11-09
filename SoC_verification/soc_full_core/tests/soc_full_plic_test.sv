// =============================================================================
// Class: soc_full_plic_test
// Purpose: Full SoC PLIC External Interrupt Verification with GPIO VIP
// =============================================================================

`ifndef SOC_FULL_PLIC_TEST_SV
`define SOC_FULL_PLIC_TEST_SV

class soc_full_plic_test extends soc_full_base_test;
    `uvm_component_utils(soc_full_plic_test)

    function new(string name = "soc_full_plic_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_phase phase);
        virtual gpio_if vif;
        phase.raise_objection(this);
        `uvm_info(get_name(), "Starting Full SoC PLIC External Interrupt Test...", UVM_LOW)

        if (!uvm_config_db#(virtual gpio_if)::get(this, "", "gpio_vif", vif)) begin
            `uvm_fatal(get_name(), "gpio_vif not found")
        end

        // Ensure bit 3 starts LOW
        vif.gpio_in <= 32'd0;

        fork
            begin
                // Wait for CPU firmware to arm PLIC and signal via Mailbox
                wait ($root.tb_soc_full_top.plic_armed);
                `uvm_info(get_name(), "CPU armed PLIC! Driving rising edge on GPIO bit 3 via VIP...", UVM_LOW)
                repeat (10) @(posedge vif.clk);
                vif.gpio_in[3] <= 1'b1; // Rising edge!
                repeat (20) @(posedge vif.clk);
                vif.gpio_in[3] <= 1'b0;
                `uvm_info(get_name(), "Injected GPIO rising edge.", UVM_LOW)
            end
            begin
                wait_for_completion(100000);
            end
        join_any

        `uvm_info(get_name(), "Completed Full SoC PLIC Test.", UVM_LOW)
        phase.drop_objection(this);
    endtask

endclass : soc_full_plic_test

`endif

