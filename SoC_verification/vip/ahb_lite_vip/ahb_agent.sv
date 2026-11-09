// =============================================================================
// Component: ahb_agent
// Purpose: UVM Agent for AHB-Lite Master VIP
// =============================================================================

`ifndef AHB_AGENT_SV
`define AHB_AGENT_SV

class ahb_agent #(parameter ADDR_WIDTH = 32, parameter DATA_WIDTH = 32) extends uvm_agent;

    `uvm_component_param_utils(ahb_agent #(ADDR_WIDTH, DATA_WIDTH))

    ahb_driver    #(ADDR_WIDTH, DATA_WIDTH) driver;
    ahb_sequencer #(ADDR_WIDTH, DATA_WIDTH) sequencer;
    ahb_monitor   #(ADDR_WIDTH, DATA_WIDTH) monitor;
    ahb_config                              cfg;

    uvm_analysis_port #(ahb_transfer #(ADDR_WIDTH, DATA_WIDTH)) item_collected_port;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db#(ahb_config)::get(this, "", "cfg", cfg)) begin
            cfg = ahb_config::type_id::create("cfg");
        end

        monitor = ahb_monitor#(ADDR_WIDTH, DATA_WIDTH)::type_id::create("monitor", this);
        monitor.cfg = cfg;

        if (cfg.is_active == UVM_ACTIVE) begin
            driver    = ahb_driver#(ADDR_WIDTH, DATA_WIDTH)::type_id::create("driver", this);
            sequencer = ahb_sequencer#(ADDR_WIDTH, DATA_WIDTH)::type_id::create("sequencer", this);
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

endclass : ahb_agent

`endif // AHB_AGENT_SV

