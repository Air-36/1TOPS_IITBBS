class branch_sequencer extends uvm_sequencer #(branch_transaction);
    `uvm_component_utils(branch_sequencer)

    function new(string name = "branch_sequencer", uvm_component parent = null);
        super.new(name, parent);
    endfunction

endclass

