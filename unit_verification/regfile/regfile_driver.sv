class regfile_driver extends uvm_driver #(regfile_transaction);
    `uvm_component_utils(regfile_driver)

    virtual regfile_if vif;
    function new(string name = "regfile_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual regfile_if)::get(this, "", "vif", vif))
            `uvm_fatal("DRIVER", "Virtual interface not found")
    endfunction

    task run_phase(uvm_phase phase);
        vif.wr_en       <= 0;
        vif.wr_addr     <= 0;
        vif.wr_data     <= 0;
        vif.rd_addr1    <= 0;
        vif.rd_addr2    <= 0;
        vif.dbg_rd_addr <= 0;

        forever begin
            seq_item_port.get_next_item(req);
            @(vif.drv_cb);
            vif.drv_cb.wr_en       <= req.wr_en;
            vif.drv_cb.wr_addr     <= req.wr_addr;
            vif.drv_cb.wr_data     <= req.wr_data;
            vif.drv_cb.rd_addr1    <= req.rd_addr1;
            vif.drv_cb.rd_addr2    <= req.rd_addr2;
            vif.drv_cb.dbg_rd_addr <= req.dbg_rd_addr;
            @(negedge vif.clk);
            seq_item_port.item_done();
        end
    endtask
endclass
