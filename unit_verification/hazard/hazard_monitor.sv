class hazard_monitor extends uvm_monitor;
    `uvm_component_utils(hazard_monitor)

    virtual hazard_if vif;
    uvm_analysis_port #(hazard_transaction) mon_ap;

    function new(string name = "hazard_monitor", uvm_component parent = null);
        super.new(name, parent);
        mon_ap = new("mon_ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual hazard_if)::get(this, "", "vif", vif))
            `uvm_fatal("MON", "Virtual interface not found")
    endfunction

    task run_phase(uvm_phase phase);
        hazard_transaction tr;
        forever begin
            #1ns;
            tr = hazard_transaction::type_id::create("tr");
            tr.Rs1D       = vif.Rs1D;
            tr.Rs2D       = vif.Rs2D;
            tr.Rs1E       = vif.Rs1E;
            tr.Rs2E       = vif.Rs2E;
            tr.RdE        = vif.RdE;
            tr.RdM        = vif.RdM;
            tr.RdW        = vif.RdW;
            tr.RegWriteM  = vif.RegWriteM;
            tr.RegWriteW  = vif.RegWriteW;
            tr.ResultSrcE = vif.ResultSrcE;
            tr.PCSrcE        = vif.PCSrcE;
            tr.TrapM         = vif.TrapM;
            tr.mretM         = vif.mretM;
            tr.LSUStallM     = vif.LSUStallM;
            tr.IFUStallF     = vif.IFUStallF;
            tr.ExternalStall = vif.ExternalStall;
            tr.ForwardAE = vif.ForwardAE;
            tr.ForwardBE = vif.ForwardBE;
            tr.StallF = vif.StallF;
            tr.StallD = vif.StallD;
            tr.StallE = vif.StallE;
            tr.StallM = vif.StallM;
            tr.StallW = vif.StallW;
            tr.FlushD = vif.FlushD;
            tr.FlushE = vif.FlushE;
            tr.FlushM = vif.FlushM;
            mon_ap.write(tr);
        end
    endtask
endclass
