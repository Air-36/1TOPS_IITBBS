class hazard_transaction extends uvm_sequence_item;

    rand bit [4:0] Rs1D;
    rand bit [4:0] Rs2D;
    rand bit [4:0] Rs1E;
    rand bit [4:0] Rs2E;
    rand bit [4:0] RdE;
    rand bit [4:0] RdM;
    rand bit [4:0] RdW;
    rand bit RegWriteM;
    rand bit RegWriteW;
    rand bit [2:0] ResultSrcE;
    rand bit PCSrcE;
    rand bit TrapM;
    rand bit mretM;
    rand bit LSUStallM;
    rand bit IFUStallF;
    rand bit ExternalStall;
    bit [1:0] ForwardAE;
    bit [1:0] ForwardBE;
    bit StallF;
    bit StallD;
    bit StallE;
    bit StallM;
    bit StallW;
    bit FlushD;
    bit FlushE;
    bit FlushM;

    `uvm_object_utils_begin(hazard_transaction)
        `uvm_field_int(Rs1D, UVM_ALL_ON)
        `uvm_field_int(Rs2D, UVM_ALL_ON)
        `uvm_field_int(Rs1E, UVM_ALL_ON)
        `uvm_field_int(Rs2E, UVM_ALL_ON)
        `uvm_field_int(RdE, UVM_ALL_ON)
        `uvm_field_int(RdM, UVM_ALL_ON)
        `uvm_field_int(RdW, UVM_ALL_ON)
        `uvm_field_int(RegWriteM, UVM_ALL_ON)
        `uvm_field_int(RegWriteW, UVM_ALL_ON)
        `uvm_field_int(ResultSrcE, UVM_ALL_ON)
        `uvm_field_int(PCSrcE, UVM_ALL_ON)
        `uvm_field_int(TrapM, UVM_ALL_ON)
        `uvm_field_int(mretM, UVM_ALL_ON)
        `uvm_field_int(LSUStallM, UVM_ALL_ON)
        `uvm_field_int(IFUStallF, UVM_ALL_ON)
        `uvm_field_int(ExternalStall, UVM_ALL_ON)
        `uvm_field_int(ForwardAE, UVM_ALL_ON)
        `uvm_field_int(ForwardBE, UVM_ALL_ON)
        `uvm_field_int(StallF, UVM_ALL_ON)
        `uvm_field_int(StallD, UVM_ALL_ON)
        `uvm_field_int(StallE, UVM_ALL_ON)
        `uvm_field_int(StallM, UVM_ALL_ON)
        `uvm_field_int(StallW, UVM_ALL_ON)
        `uvm_field_int(FlushD, UVM_ALL_ON)
        `uvm_field_int(FlushE, UVM_ALL_ON)
        `uvm_field_int(FlushM, UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "hazard_transaction");
        super.new(name);
    endfunction
endclass
