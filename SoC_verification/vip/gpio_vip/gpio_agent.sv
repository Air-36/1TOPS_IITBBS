// =============================================================================
// Component: gpio_agent
// Purpose: UVM Agent for GPIO VIP
// =============================================================================

`ifndef GPIO_AGENT_SV
`define GPIO_AGENT_SV

class gpio_agent extends uvm_agent;

    `uvm_component_utils(gpio_agent)

    gpio_driver    driver;
    gpio_sequencer sequencer;
    gpio_monitor   monitor;
    gpio_config    cfg;

    uvm_analysis_port #(gpio_item) item_collected_port;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db#(gpio_config)::get(this, "", "cfg", cfg)) begin
            cfg = gpio_config::type_id::create("cfg");
        end

        monitor = gpio_monitor::type_id::create("monitor", this);
        monitor.cfg = cfg;

        if (cfg.is_active == UVM_ACTIVE) begin
            driver    = gpio_driver::type_id::create("driver", this);
            sequencer = gpio_sequencer::type_id::create("sequencer", this);
            driver.cfg = cfg;
        end
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        item_collected_port = monitor.item_collected_port;

        if (cfg.is_active == UVM_ACTIVE) begin
            driver.seq_item_port.connect(sequencer.seq_item_export);
        end
    endfunction

endclass : gpio_agent

`endif // GPIO_AGENT_SV

