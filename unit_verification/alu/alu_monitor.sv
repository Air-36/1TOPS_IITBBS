class alu_monitor extends uvm_monitor;
    `uvm_component_utils(alu_monitor)

    virtual alu_if vif;
    uvm_analysis_port #(alu_transaction) mon_ap;

    function new(string name = "alu_monitor",
                 uvm_component parent = null);
        super.new(name, parent);
        mon_ap = new("mon_ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual alu_if)::get(this, "", "vif", vif)) begin
           `uvm_fatal("ALU_MON", "Virtual interface not found")
        end
    endfunction

    task run_phase(uvm_phase phase);
        alu_transaction tr;
        @(posedge vif.clk);
        forever begin
            @(vif.mon_cb);
            tr = alu_transaction::type_id::create("tr");
            
            // Capture DUT inputs
            tr.a        = vif.mon_cb.a;
            tr.b        = vif.mon_cb.b;
            tr.alu_ctrl = vif.mon_cb.alu_ctrl;

            // Capture DUT outputs
            tr.alu_out = vif.mon_cb.alu_out;
            tr.zero    = vif.mon_cb.zero;
            tr.less    = vif.mon_cb.less;
            tr.less_u  = vif.mon_cb.less_u;

            // Send transaction
            mon_ap.write(tr);
        end
    endtask
endclass
