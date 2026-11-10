class hazard_sequencer extends uvm_sequencer #(hazard_transaction);
    `uvm_component_utils(hazard_sequencer)

    function new(string name = "hazard_sequencer", uvm_component parent = null);
        super.new(name, parent);
    endfunction

endclass
