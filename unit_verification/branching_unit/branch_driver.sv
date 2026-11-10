class branch_driver extends uvm_driver #(branch_transaction);
    `uvm_component_utils(branch_driver)

    virtual branch_if vif;

    function new(string name = "branch_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual branch_if)::get(this, "", "vif", vif))
            `uvm_fatal("DRV", "Virtual interface not found")
    endfunction

    task run_phase(uvm_phase phase);
        branch_transaction tx;
        forever begin
            seq_item_port.get_next_item(tx);
            vif.funct3 = tx.funct3;
            vif.Zero   = tx.Zero;
            vif.Less   = tx.Less;
            vif.LessU  = tx.LessU;
            #1ns;
            seq_item_port.item_done();
        end
    endtask
endclass

