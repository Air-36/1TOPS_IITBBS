class controller_transaction extends uvm_sequence_item;

    rand bit [31:0] InstrD;
    bit [2:0] ResultSrc;
    bit MemWrite;
    bit ALUSrc;
    bit RegWrite;
    bit Branch;
    bit Jump;
    bit Jalr;
    bit [1:0] ImmSrc;
    bit [3:0] ALUControl;
    bit CSRRead;
    bit CSRWrite;
    bit mretD;
    bit wfiD;
    bit ecallD;
    bit ebreakD;
    bit IllegalInstrD;
    bit FenceID;

    `uvm_object_utils_begin(controller_transaction)
        `uvm_field_int(InstrD, UVM_ALL_ON)
        `uvm_field_int(ResultSrc, UVM_ALL_ON)
        `uvm_field_int(MemWrite, UVM_ALL_ON)
        `uvm_field_int(ALUSrc, UVM_ALL_ON)
        `uvm_field_int(RegWrite, UVM_ALL_ON)
        `uvm_field_int(Branch, UVM_ALL_ON)
        `uvm_field_int(Jump, UVM_ALL_ON)
        `uvm_field_int(Jalr, UVM_ALL_ON)
        `uvm_field_int(ImmSrc, UVM_ALL_ON)
        `uvm_field_int(ALUControl, UVM_ALL_ON)
        `uvm_field_int(CSRRead, UVM_ALL_ON)
        `uvm_field_int(CSRWrite, UVM_ALL_ON)
        `uvm_field_int(mretD, UVM_ALL_ON)
        `uvm_field_int(wfiD, UVM_ALL_ON)
        `uvm_field_int(ecallD, UVM_ALL_ON)
        `uvm_field_int(ebreakD, UVM_ALL_ON)
        `uvm_field_int(IllegalInstrD, UVM_ALL_ON)
        `uvm_field_int(FenceID, UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "controller_transaction");
        super.new(name);
    endfunction

endclass
