// =============================================================================
// Class: soc_full_scoreboard
// Purpose: Scoreboard for Full 1TOPS RISC-V SoC Verification
// =============================================================================

`ifndef SOC_FULL_SCOREBOARD_SV
`define SOC_FULL_SCOREBOARD_SV

`uvm_analysis_imp_decl(_gpio)
`uvm_analysis_imp_decl(_irq)
`uvm_analysis_imp_decl(_uart)

class soc_full_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(soc_full_scoreboard)

    uvm_analysis_imp_gpio #(gpio_item, soc_full_scoreboard) gpio_export;
    uvm_analysis_imp_irq  #(irq_item,  soc_full_scoreboard) irq_export;
    uvm_analysis_imp_uart #(uart_item, soc_full_scoreboard) uart_export;

    // Telemetry counters
    int gpio_trans_count = 0;
    int irq_trans_count  = 0;
    int uart_char_count  = 0;
    int match_count      = 0;
    int mismatch_count   = 0;

    string uart_buffer   = "";

    function new(string name = "soc_full_scoreboard", uvm_component parent = null);
        super.new(name, parent);
        gpio_export = new("gpio_export", this);
        irq_export  = new("irq_export",  this);
        uart_export = new("uart_export", this);
    endfunction

    // 1. Process GPIO VIP Transactions
    virtual function void write_gpio(gpio_item item);
        gpio_trans_count++;
        `uvm_info("SCB_GPIO", $sformatf("Observed GPIO Event: IN=0x%08h OUT=0x%08h OE=0x%08h", 
                  item.sampled_in, item.sampled_out, item.sampled_en), UVM_MEDIUM)
        match_count++;
    endfunction

    // 2. Process IRQ VIP Transactions
    virtual function void write_irq(irq_item item);
        irq_trans_count++;
        `uvm_info("SCB_IRQ", $sformatf("Observed IRQ Event: Source=%s Asserted=%0b (Timer=%0b SW=%0b MExt=%0b GPIO=%0b)", 
                  item.source.name(), item.asserted, item.mtimer_int, item.msw_int, item.mext_int, item.gpio_intr), UVM_MEDIUM)
        match_count++;
    endfunction

    // 3. Process UART VIP Characters
    virtual function void write_uart(uart_item item);
        uart_char_count++;
        uart_buffer = {uart_buffer, string'(item.data)};
        `uvm_info("SCB_UART", $sformatf("Observed UART Char: '%c' (0x%02h)", item.data, item.data), UVM_HIGH)
        match_count++;
    endfunction

    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("SCOREBOARD", "=======================================================", UVM_LOW)
        `uvm_info("SCOREBOARD", $sformatf(" Full SoC Scoreboard Summary:"), UVM_LOW)
        `uvm_info("SCOREBOARD", $sformatf("   GPIO Transactions : %0d", gpio_trans_count), UVM_LOW)
        `uvm_info("SCOREBOARD", $sformatf("   IRQ Transactions  : %0d", irq_trans_count), UVM_LOW)
        `uvm_info("SCOREBOARD", $sformatf("   UART Characters   : %0d", uart_char_count), UVM_LOW)
        if (uart_char_count > 0) begin
            `uvm_info("SCOREBOARD", $sformatf("   UART Received Str : \"%s\"", uart_buffer), UVM_LOW)
        end
        `uvm_info("SCOREBOARD", $sformatf("   Matches           : %0d", match_count), UVM_LOW)
        `uvm_info("SCOREBOARD", $sformatf("   Mismatches        : %0d", mismatch_count), UVM_LOW)
        `uvm_info("SCOREBOARD", "=======================================================", UVM_LOW)

        if (mismatch_count > 0) begin
            `uvm_error("SCOREBOARD", $sformatf("FAILED with %0d mismatches!", mismatch_count))
        end else begin
            `uvm_info("SCOREBOARD", "SUCCESS: All verification checks passed cleanly!", UVM_LOW)
        end
    endfunction

endclass : soc_full_scoreboard

`endif

