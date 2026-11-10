class hazard_agent extends uvm_agent;
    `uvm_component_utils(hazard_agent)

    hazard_sequencer seqr;
    hazard_driver    drv;
    hazard_monitor   mon;

    function new(string name = "hazard_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        seqr = hazard_sequencer::type_id::create("seqr", this);
        drv  = hazard_driver::type_id::create("drv", this);
        mon  = hazard_monitor::type_id::create("mon", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        drv.seq_item_port.connect(seqr.seq_item_export);
    endfunction
endclass
