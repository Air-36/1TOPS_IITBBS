// =============================================================================
// Sequence Item: apb_transfer
// Purpose: AMBA 3 APB Transaction Representation
// =============================================================================

`ifndef APB_TRANSFER_SV
`define APB_TRANSFER_SV

class apb_transfer #(parameter ADDR_WIDTH = 32, parameter DATA_WIDTH = 32) extends uvm_sequence_item;

    rand bit [ADDR_WIDTH-1:0]   addr;
    rand bit [DATA_WIDTH-1:0]   data;
    rand bit [DATA_WIDTH/8-1:0] strb;
    rand bit                    write;

    bit [DATA_WIDTH-1:0]        rdata;
    bit                         slverr;
    int                         wait_cycles;

    `uvm_object_utils_begin(apb_transfer)
        `uvm_field_int(addr,        UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(data,        UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(strb,        UVM_ALL_ON | UVM_BIN)
        `uvm_field_int(write,       UVM_ALL_ON)
        `uvm_field_int(rdata,       UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(slverr,      UVM_ALL_ON)
        `uvm_field_int(wait_cycles, UVM_ALL_ON | UVM_DEC)
    `uvm_object_utils_end

    constraint c_default {
        soft strb == '1;
    }

    function new(string name = "apb_transfer");
        super.new(name);
        strb = '1;
        write = 0;
        addr  = 0;
        data  = 0;
    endfunction

endclass : apb_transfer

`endif // APB_TRANSFER_SV

