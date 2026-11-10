class branch_transaction extends uvm_sequence_item;

    rand bit [2:0] funct3;
    rand bit       Zero;
    rand bit       Less;
    rand bit       LessU;
    bit            Branch;

    `uvm_object_utils_begin(branch_transaction)
        `uvm_field_int(funct3, UVM_ALL_ON)
        `uvm_field_int(Zero, UVM_ALL_ON)
        `uvm_field_int(Less, UVM_ALL_ON)
        `uvm_field_int(LessU, UVM_ALL_ON)
        `uvm_field_int(Branch, UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "branch_transaction");
        super.new(name);
    endfunction

endclass

