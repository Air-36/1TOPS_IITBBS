// =============================================================================
// Component: apb_agent
// Purpose: UVM Agent for APB Master VIP
// =============================================================================

`ifndef APB_AGENT_SV
`define APB_AGENT_SV

class apb_agent #(parameter ADDR_WIDTH = 32, parameter DATA_WIDTH = 32) extends uvm_agent;

    `uvm_component_param_utils(apb_agent #(ADDR_WIDTH, DATA_WIDTH))

    apb_driver    #(ADDR_WIDTH, DATA_WIDTH) driver;
    apb_sequencer #(ADDR_WIDTH, DATA_WIDTH) sequencer;
    apb_monitor   #(ADDR_WIDTH, DATA_WIDTH) monitor;
    apb_config                              cfg;

    uvm_analysis_port #(apb_transfer #(ADDR_WIDTH, DATA_WIDTH)) item_collected_port;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db#(apb_config)::get(this, "", "cfg", cfg)) begin
            cfg = apb_config::type_id::create("cfg");
        end

        monitor = apb_monitor#(ADDR_WIDTH, DATA_WIDTH)::type_id::create("monitor", this);
        monitor.cfg = cfg;

        if (cfg.is_active == UVM_ACTIVE) begin
            driver    = apb_driver#(ADDR_WIDTH, DATA_WIDTH)::type_id::create("driver", this);
            sequencer = apb_sequencer#(ADDR_WIDTH, DATA_WIDTH)::type_id::create("sequencer", this);
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

endclass : apb_agent

`endif // APB_AGENT_SV

