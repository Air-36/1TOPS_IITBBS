// =============================================================================
// Component: soc_scoreboard
// Purpose: Multi-port Scoreboard for Coreless SoC Integration Verification
// =============================================================================

`ifndef SOC_SCOREBOARD_SV
`define SOC_SCOREBOARD_SV

`uvm_analysis_imp_decl(_ahb)
`uvm_analysis_imp_decl(_gpio)
`uvm_analysis_imp_decl(_irq)

class soc_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(soc_scoreboard)

    uvm_analysis_imp_ahb  #(ahb_transfer#(32, 32), soc_scoreboard) ahb_export;
    uvm_analysis_imp_gpio #(gpio_item,             soc_scoreboard) gpio_export;
    uvm_analysis_imp_irq  #(irq_item,              soc_scoreboard) irq_export;

    int total_ahb_trans   = 0;
    int total_gpio_events = 0;
    int total_irq_events  = 0;
    int error_count       = 0;

    // Shadow memory for data RAM (0x8001_0000 - 0x8001_7FFF)
    bit [31:0] shadow_dram [bit [31:0]];

    function new(string name, uvm_component parent);
        super.new(name, parent);
        ahb_export  = new("ahb_export", this);
        gpio_export = new("gpio_export", this);
        irq_export  = new("irq_export", this);
    endfunction

    virtual function void write_ahb(ahb_transfer#(32, 32) tr);
        total_ahb_trans++;

        // Track DRAM write/read integrity
        if (tr.addr >= 32'h8001_0000 && tr.addr < 32'h8001_8000) begin
            if (tr.write) begin
                shadow_dram[tr.addr] = tr.data;
            end else if (shadow_dram.exists(tr.addr)) begin
                if (tr.rdata !== shadow_dram[tr.addr]) begin
                    `uvm_error("SCB_DRAM_MISMATCH",
                               $sformatf("[DRAM 0x%08h] Read: 0x%08h != Expected: 0x%08h",
                                         tr.addr, tr.rdata, shadow_dram[tr.addr]))
                    error_count++;
                end
            end
        end

        // Check for bus response errors on mapped regions
        if (tr.resp == 1'b1) begin
            `uvm_warning("SCB_AHB_ERROR_RESP", $sformatf("AHB transfer to 0x%08h received ERROR response!", tr.addr))
        end
    endfunction

    virtual function void write_gpio(gpio_item item);
        total_gpio_events++;
    endfunction

    virtual function void write_irq(irq_item item);
        total_irq_events++;
    endfunction

    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("SOC_SCB_REPORT", "==================================================", UVM_LOW)
        `uvm_info("SOC_SCB_REPORT", $sformatf(" Total AHB Bus Transfers Monitored: %0d", total_ahb_trans), UVM_LOW)
        `uvm_info("SOC_SCB_REPORT", $sformatf(" Total GPIO Pin Events Monitored:   %0d", total_gpio_events), UVM_LOW)
        `uvm_info("SOC_SCB_REPORT", $sformatf(" Total Interrupt Events Monitored:  %0d", total_irq_events), UVM_LOW)
        `uvm_info("SOC_SCB_REPORT", $sformatf(" Total Scoreboard Errors:           %0d", error_count), UVM_LOW)
        `uvm_info("SOC_SCB_REPORT", "==================================================", UVM_LOW)
    endfunction

endclass : soc_scoreboard

`endif // SOC_SCOREBOARD_SV

