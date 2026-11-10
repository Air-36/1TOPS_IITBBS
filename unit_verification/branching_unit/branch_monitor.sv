class branch_monitor extends uvm_monitor;
    `uvm_component_utils(branch_monitor)

    virtual branch_if vif;
    uvm_analysis_port #(branch_transaction) mon_ap;

    function new(string name = "branch_monitor", uvm_component parent = null);
        super.new(name, parent);
        mon_ap = new("mon_ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual branch_if)::get(this, "", "vif", vif))
            `uvm_fatal("MON", "Virtual interface not found")
    endfunction

    task run_phase(uvm_phase phase);
        branch_transaction tx;
        forever begin
            #1ns;
            tx = branch_transaction::type_id::create("tx");
            tx.funct3 = vif.funct3;
            tx.Zero   = vif.Zero;
            tx.Less   = vif.Less;
            tx.LessU  = vif.LessU;
            tx.Branch = vif.Branch;
            mon_ap.write(tx);
        end
    endtask
endclass

