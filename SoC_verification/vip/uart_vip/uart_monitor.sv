// =============================================================================
// Class: uart_monitor
// Purpose: UVM Monitor for UART transmitter stream
// =============================================================================

`ifndef UART_MONITOR_SV
`define UART_MONITOR_SV

class uart_monitor extends uvm_monitor;
    `uvm_component_utils(uart_monitor)

    virtual uart_if vif;
    uvm_analysis_port #(uart_item) ap;

    function new(string name = "uart_monitor", uvm_component parent = null);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual uart_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("UART_MON", "virtual uart_if not found in uvm_config_db")
        end
    endfunction

    virtual task run_phase(uvm_phase phase);
        // Passive monitor observing UART interface
        forever begin
            @(posedge vif.clk);
        end
    endtask

    // Direct byte observation hook called by tb monitor on THR write
    virtual function void record_char(bit [7:0] ch);
        uart_item item = uart_item::type_id::create("uart_item");
        item.data = ch;
        item.timestamp = $time;
        ap.write(item);
    endfunction

endclass : uart_monitor

`endif

