class regfile_sequencer extends uvm_sequencer #(regfile_transaction);
    `uvm_component_utils(regfile_sequencer)

    function new(string name = "regfile_sequencer", uvm_component parent = null);
        super.new(name, parent);
    endfunction
endclass
