class alu_driver extends uvm_driver #(alu_transaction);
    `uvm_component_utils(alu_driver)

    virtual alu_if vif;

    function new(string name = "alu_driver",uvm_component parent = null);
        super.new(name, parent);
    endfunction

    //virtual interface
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual alu_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("ALU_DRV", "Virtual interface not found")
        end
    endfunction

    task run_phase(uvm_phase phase);
        alu_transaction req;
        forever begin
            seq_item_port.get_next_item(req);
            // Drive inputs 
            @(vif.drv_cb);
            vif.drv_cb.a        <= req.a;
            vif.drv_cb.b        <= req.b;
            vif.drv_cb.alu_ctrl <= req.alu_ctrl;
            @(vif.mon_cb);
            seq_item_port.item_done();
        end
    endtask
endclass
