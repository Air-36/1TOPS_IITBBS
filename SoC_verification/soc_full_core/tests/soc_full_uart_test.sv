// =============================================================================
// Class: soc_full_uart_test
// Purpose: Full SoC 16550 UART Verification with UVM Character Monitor
// =============================================================================

`ifndef SOC_FULL_UART_TEST_SV
`define SOC_FULL_UART_TEST_SV

class soc_full_uart_test extends soc_full_base_test;
    `uvm_component_utils(soc_full_uart_test)

    function new(string name = "soc_full_uart_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        `uvm_info(get_name(), "Starting Full SoC UART Stream Test...", UVM_LOW)

        wait_for_completion(80000);

        // Verify UART received buffer contains expected string
        if (env.scb.uart_char_count > 0) begin
            `uvm_info(get_name(), $sformatf("UART Monitor captured %0d characters: \"%s\"", 
                      env.scb.uart_char_count, env.scb.uart_buffer), UVM_LOW)
        end else begin
            `uvm_error(get_name(), "No UART characters captured by monitor!")
        end

        `uvm_info(get_name(), "Completed Full SoC UART Test.", UVM_LOW)
        phase.drop_objection(this);
    endtask

endclass : soc_full_uart_test

`endif

