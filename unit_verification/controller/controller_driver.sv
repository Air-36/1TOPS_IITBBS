class controller_driver extends uvm_driver #(controller_transaction);
    `uvm_component_utils(controller_driver)

    virtual controller_if vif;

    function new(string name = "controller_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual controller_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "controller_if not found")
    endfunction

    task run_phase(uvm_phase phase);
        controller_transaction trans;
        vif.InstrD = '0;
        vif.sample_req = 0;
        
        forever begin
            seq_item_port.get_next_item(trans);
            vif.InstrD = trans.InstrD;
            #1ns;
            vif.sample_req = 1;
            wait(vif.sample_ack == 1);
            vif.sample_req = 0;
            wait(vif.sample_ack == 0);
            seq_item_port.item_done();
        end
    endtask

endclass
