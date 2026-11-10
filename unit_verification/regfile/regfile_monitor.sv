class regfile_monitor extends uvm_monitor;
    `uvm_component_utils(regfile_monitor)

    virtual regfile_if vif;
    uvm_analysis_port #(regfile_transaction) mon_ap;
    
    function new(string name = "regfile_monitor", uvm_component parent = null);
        super.new(name, parent);
        mon_ap = new("mon_ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual regfile_if)::get(this, "", "vif", vif))
            `uvm_fatal("MONITOR", "Virtual interface not found")
    endfunction

    task run_phase(uvm_phase phase);
        regfile_transaction tx;
        forever begin
            @(vif.mon_cb);
            tx = regfile_transaction::type_id::create("tx");
            tx.wr_en       = vif.mon_cb.wr_en;
            tx.wr_addr     = vif.mon_cb.wr_addr;
            tx.wr_data     = vif.mon_cb.wr_data;
            tx.rd_addr1    = vif.mon_cb.rd_addr1;
            tx.rd_addr2    = vif.mon_cb.rd_addr2;
            tx.dbg_rd_addr = vif.mon_cb.dbg_rd_addr;
            tx.pre_rd_data1 = vif.mon_cb.rd_data1;
            tx.pre_rd_data2 = vif.mon_cb.rd_data2;
            tx.pre_dbg_data = vif.mon_cb.dbg_rd_data;
            #1;
            tx.rd_data1 = vif.rd_data1;
            tx.rd_data2 = vif.rd_data2;
            tx.dbg_rd_data = vif.dbg_rd_data;
            mon_ap.write(tx);
        end
    endtask
endclass
