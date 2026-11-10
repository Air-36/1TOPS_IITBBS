class hazard_driver extends uvm_driver #(hazard_transaction);
    `uvm_component_utils(hazard_driver)

    virtual hazard_if vif;

    function new(string name = "hazard_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual hazard_if)::get(this, "", "vif", vif))
            `uvm_fatal("DRV", "Virtual interface not found")
    endfunction

    task run_phase(uvm_phase phase);
        hazard_transaction req;

        // Initialize all DUT inputs
        vif.Rs1D = 0;
        vif.Rs2D = 0;
        vif.Rs1E = 0;
        vif.Rs2E = 0;
        vif.RdE = 0;
        vif.RdM = 0;
        vif.RdW = 0;
        vif.RegWriteM = 0;
        vif.RegWriteW = 0;
        vif.ResultSrcE = 0;
        vif.PCSrcE = 0;
        vif.TrapM = 0;
        vif.mretM = 0;
        vif.LSUStallM = 0;
        vif.IFUStallF = 0;
        vif.ExternalStall = 0;

        forever begin
            seq_item_port.get_next_item(req);
            vif.Rs1D = req.Rs1D;
            vif.Rs2D = req.Rs2D;
            vif.Rs1E = req.Rs1E;
            vif.Rs2E = req.Rs2E;
            vif.RdE  = req.RdE;
            vif.RdM = req.RdM;
            vif.RdW = req.RdW;
            vif.RegWriteM = req.RegWriteM;
            vif.RegWriteW = req.RegWriteW;
            vif.ResultSrcE = req.ResultSrcE;
            vif.PCSrcE = req.PCSrcE;
            vif.TrapM = req.TrapM;
            vif.mretM = req.mretM;
            vif.LSUStallM = req.LSUStallM;
            vif.IFUStallF = req.IFUStallF;
            vif.ExternalStall = req.ExternalStall;
            #1ns;
            seq_item_port.item_done();
        end
    endtask
endclass
