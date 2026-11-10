class branch_agent extends uvm_agent;
    `uvm_component_utils(branch_agent)

    branch_sequencer seqr;
    branch_driver    drv;
    branch_monitor   mon;

    function new(string name = "branch_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        seqr = branch_sequencer::type_id::create("seqr", this);
        drv  = branch_driver::type_id::create("drv", this);
        mon  = branch_monitor::type_id::create("mon", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        drv.seq_item_port.connect(seqr.seq_item_export);
    endfunction

endclass
