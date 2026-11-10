class alu_transaction extends uvm_sequence_item;

    // DUT inputs
    rand bit [31:0] a;
    rand bit [31:0] b;
    rand bit [3:0]  alu_ctrl;

    // DUT outputs
    bit [31:0] alu_out;
    bit        zero;
    bit        less;
    bit        less_u;

    // Only valid ALU operations: 0 to 9
    constraint valid_operation {
        alu_ctrl inside {[4'd0:4'd9]};
    }

    `uvm_object_utils_begin(alu_transaction)
        `uvm_field_int(a,        UVM_ALL_ON)
        `uvm_field_int(b,        UVM_ALL_ON)
        `uvm_field_int(alu_ctrl, UVM_ALL_ON)
        `uvm_field_int(alu_out,  UVM_ALL_ON)
        `uvm_field_int(zero,     UVM_ALL_ON)
        `uvm_field_int(less,     UVM_ALL_ON)
        `uvm_field_int(less_u,   UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "alu_transaction");
        super.new(name);
    endfunction

endclass
