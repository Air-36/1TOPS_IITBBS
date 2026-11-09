// =============================================================================
// Sequence Item: ahb_transfer
// Purpose: AHB-Lite Transaction Representation
// =============================================================================

`ifndef AHB_TRANSFER_SV
`define AHB_TRANSFER_SV

class ahb_transfer #(parameter ADDR_WIDTH = 32, parameter DATA_WIDTH = 32) extends uvm_sequence_item;

    typedef enum logic [1:0] {
        TR_IDLE   = 2'b00,
        TR_BUSY   = 2'b01,
        TR_NONSEQ = 2'b10,
        TR_SEQ    = 2'b11
    } trans_type_e;

    typedef enum logic [2:0] {
        SZ_BYTE     = 3'b000,
        SZ_HALFWORD = 3'b001,
        SZ_WORD     = 3'b010,
        SZ_DOUBLE   = 3'b011
    } size_type_e;

    typedef enum logic [2:0] {
        BURST_SINGLE = 3'b000,
        BURST_INCR   = 3'b001,
        BURST_WRAP4  = 3'b010,
        BURST_INCR4  = 3'b011,
        BURST_WRAP8  = 3'b100,
        BURST_INCR8  = 3'b101,
        BURST_WRAP16 = 3'b110,
        BURST_INCR16 = 3'b111
    } burst_type_e;

    // Stimulus fields
    rand bit [ADDR_WIDTH-1:0]     addr;
    rand bit [DATA_WIDTH-1:0]     data;
    rand bit [DATA_WIDTH/8-1:0]   strb;
    rand bit                      write;
    rand trans_type_e             trans;
    rand size_type_e              size;
    rand burst_type_e             burst;
    rand bit [3:0]                prot;
    rand bit                      mastlock;

    // Response fields
    bit [DATA_WIDTH-1:0]          rdata;
    bit                           resp;   // 0: OKAY, 1: ERROR
    int                           wait_cycles;

    `uvm_object_utils_begin(ahb_transfer)
        `uvm_field_int(addr,        UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(data,        UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(strb,        UVM_ALL_ON | UVM_BIN)
        `uvm_field_int(write,       UVM_ALL_ON)
        `uvm_field_enum(trans_type_e, trans, UVM_ALL_ON)
        `uvm_field_enum(size_type_e,  size,  UVM_ALL_ON)
        `uvm_field_enum(burst_type_e, burst, UVM_ALL_ON)
        `uvm_field_int(prot,        UVM_ALL_ON)
        `uvm_field_int(mastlock,    UVM_ALL_ON)
        `uvm_field_int(rdata,       UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(resp,        UVM_ALL_ON)
        `uvm_field_int(wait_cycles, UVM_ALL_ON | UVM_DEC)
    `uvm_object_utils_end

    constraint c_default {
        trans inside {TR_NONSEQ, TR_IDLE};
        size  == SZ_WORD;
        burst == BURST_SINGLE;
        prot  == 4'b0011;
        mastlock == 1'b0;
        soft strb == 4'b1111;
    }

    function new(string name = "ahb_transfer");
        super.new(name);
        trans = TR_NONSEQ;
        size  = SZ_WORD;
        burst = BURST_SINGLE;
        prot  = 4'b0011;
        strb  = 4'b1111;
        write = 0;
        addr  = 0;
        data  = 0;
    endfunction

endclass : ahb_transfer

`endif // AHB_TRANSFER_SV

