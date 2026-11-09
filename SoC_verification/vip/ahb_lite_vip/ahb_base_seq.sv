// =============================================================================
// Sequence: ahb_base_seq & helper sequences
// Purpose: Base sequence and helper tasks for AHB-Lite VIP
// =============================================================================

`ifndef AHB_BASE_SEQ_SV
`define AHB_BASE_SEQ_SV

class ahb_base_seq #(parameter ADDR_WIDTH = 32, parameter DATA_WIDTH = 32)
    extends uvm_sequence #(ahb_transfer #(ADDR_WIDTH, DATA_WIDTH));

    `uvm_object_param_utils(ahb_base_seq #(ADDR_WIDTH, DATA_WIDTH))

    function new(string name = "ahb_base_seq");
        super.new(name);
    endfunction

    // Helper task: Write 32-bit word
    virtual task write_word(input bit [ADDR_WIDTH-1:0] addr,
                            input bit [DATA_WIDTH-1:0] data,
                            input bit [DATA_WIDTH/8-1:0] strb = '1);
        ahb_transfer #(ADDR_WIDTH, DATA_WIDTH) tr;
        `uvm_create(tr)
        tr.addr  = addr;
        tr.data  = data;
        tr.strb  = strb;
        tr.write = 1'b1;
        tr.trans = ahb_transfer#(ADDR_WIDTH, DATA_WIDTH)::TR_NONSEQ;
        tr.size  = ahb_transfer#(ADDR_WIDTH, DATA_WIDTH)::SZ_WORD;
        tr.burst = ahb_transfer#(ADDR_WIDTH, DATA_WIDTH)::BURST_SINGLE;
        `uvm_send(tr)
    endtask

    // Helper task: Read 32-bit word
    virtual task read_word(input  bit [ADDR_WIDTH-1:0] addr,
                           output bit [DATA_WIDTH-1:0] data,
                           output bit                  resp);
        ahb_transfer #(ADDR_WIDTH, DATA_WIDTH) tr;
        `uvm_create(tr)
        tr.addr  = addr;
        tr.write = 1'b0;
        tr.trans = ahb_transfer#(ADDR_WIDTH, DATA_WIDTH)::TR_NONSEQ;
        tr.size  = ahb_transfer#(ADDR_WIDTH, DATA_WIDTH)::SZ_WORD;
        tr.burst = ahb_transfer#(ADDR_WIDTH, DATA_WIDTH)::BURST_SINGLE;
        `uvm_send(tr)
        data = tr.rdata;
        resp = tr.resp;
    endtask

    // Helper task: Read and check expected word
    virtual task read_check(input bit [ADDR_WIDTH-1:0] addr,
                            input bit [DATA_WIDTH-1:0] exp_data,
                            input bit [DATA_WIDTH-1:0] mask = '1,
                            input string desc = "");
        bit [DATA_WIDTH-1:0] rd_val;
        bit resp;
        read_word(addr, rd_val, resp);
        if ((rd_val & mask) !== (exp_data & mask)) begin
            `uvm_error("RD_CHK_FAIL", $sformatf("%s [AHB 0x%08h] Read: 0x%08h != Exp: 0x%08h (mask: 0x%08h)",
                                                desc, addr, rd_val, exp_data, mask))
        end else begin
            `uvm_info("RD_CHK_PASS", $sformatf("%s [AHB 0x%08h] Read matched: 0x%08h (mask: 0x%08h)",
                                               desc, addr, rd_val, mask), UVM_HIGH)
        end
    endtask

    virtual task body();
        // Base sequence body (can be overridden)
    endtask

endclass : ahb_base_seq

`endif // AHB_BASE_SEQ_SV

