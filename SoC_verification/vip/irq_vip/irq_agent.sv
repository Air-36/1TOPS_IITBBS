// =============================================================================
// Component: irq_agent
// Purpose: UVM Agent for Interrupt Observation
// =============================================================================

`ifndef IRQ_AGENT_SV
`define IRQ_AGENT_SV

class irq_agent extends uvm_agent;

    `uvm_component_utils(irq_agent)

    irq_monitor monitor;
    uvm_analysis_port #(irq_item) item_collected_port;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        monitor = irq_monitor::type_id::create("monitor", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        item_collected_port = monitor.item_collected_port;
    endfunction

endclass : irq_agent

`endif // IRQ_AGENT_SV

