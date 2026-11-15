class controller_monitor extends uvm_monitor;
    `uvm_component_utils(controller_monitor)

    virtual controller_if vif;
    uvm_analysis_port #(controller_transaction) ap;

    function new(string name = "controller_monitor", uvm_component parent = null);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual controller_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "controller_if not found")
    endfunction

    task run_phase(uvm_phase phase);
        controller_transaction trans;

        forever begin
            wait(vif.sample_req == 1);
            #1ps;
            trans = controller_transaction::type_id::create("trans");
            trans.InstrD = vif.InstrD;
            trans.ResultSrc  = vif.ResultSrc;
            trans.MemWrite   = vif.MemWrite;
            trans.ALUSrc     = vif.ALUSrc;
            trans.RegWrite   = vif.RegWrite;
            trans.Branch     = vif.Branch;
            trans.Jump       = vif.Jump;
            trans.Jalr       = vif.Jalr;
            trans.ImmSrc     = vif.ImmSrc;
            trans.ALUControl = vif.ALUControl;
            trans.CSRRead    = vif.CSRRead;
            trans.CSRWrite   = vif.CSRWrite;
            trans.mretD      = vif.mretD;
            trans.wfiD       = vif.wfiD;
            trans.ecallD     = vif.ecallD;
            trans.ebreakD    = vif.ebreakD;
            trans.IllegalInstrD = vif.IllegalInstrD;
            trans.FenceID       = vif.FenceID;
            ap.write(trans);
            vif.sample_ack = 1;
            wait(vif.sample_req == 0);
            vif.sample_ack = 0;
        end
    endtask

endclass
