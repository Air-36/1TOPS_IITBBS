// =============================================================================
// Class: soc_full_boot_test
// Purpose: Verifies synthesizable Boot ROM execution in Boot Mode 0 & Boot Mode 1
// =============================================================================

`ifndef SOC_FULL_BOOT_TEST_SV
`define SOC_FULL_BOOT_TEST_SV

class soc_full_boot_test extends soc_full_base_test;
    `uvm_component_utils(soc_full_boot_test)

    function new(string name = "soc_full_boot_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        `uvm_info(get_name(), "Starting Full SoC Boot ROM Bring-Up Test...", UVM_LOW)

        if (ctrl_vif.boot_mode_pin) begin
            env.cov.sample_boot(2'd1); // SPI Flash Boot
            `uvm_info(get_name(), "Testing Boot Mode 1: SPI Flash Bootloader -> IMEM Jump", UVM_LOW)
        end else begin
            env.cov.sample_boot(2'd0); // Internal ROM Boot
            `uvm_info(get_name(), "Testing Boot Mode 0: Internal ROM Diagnostic & main()", UVM_LOW)
        end

        // Wait for Boot ROM to execute and write PASS to scratchpad / mailbox
        wait_for_completion(80000);

        `uvm_info(get_name(), "Completed Full SoC Boot ROM Test.", UVM_LOW)
        phase.drop_objection(this);
    endtask

endclass : soc_full_boot_test

`endif

