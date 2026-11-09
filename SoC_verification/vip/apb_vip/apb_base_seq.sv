// =============================================================================
// Sequence: apb_base_seq
// Purpose: Base sequence and helper tasks for APB VIP
// =============================================================================

`ifndef APB_BASE_SEQ_SV
`define APB_BASE_SEQ_SV

class apb_base_seq #(parameter ADDR_WIDTH = 32, parameter DATA_WIDTH = 32)
    extends uvm_sequence #(apb_transfer #(ADDR_WIDTH, DATA_WIDTH));

    `uvm_object_param_utils(apb_base_seq #(ADDR_WIDTH, DATA_WIDTH))

    function new(string name = "apb_base_seq");
        super.new(name);
    endfunction

    // Write word
    virtual task write(input bit [ADDR_WIDTH-1:0]   addr,
                       input bit [DATA_WIDTH-1:0]   data,
                       input bit [DATA_WIDTH/8-1:0] strb = '1);
        apb_transfer #(ADDR_WIDTH, DATA_WIDTH) tr;
        `uvm_create(tr)
        tr.addr  = addr;
        tr.data  = data;
        tr.strb  = strb;
        tr.write = 1'b1;
        `uvm_send(tr)
    endtask

    // Read word
    virtual task read(input  bit [ADDR_WIDTH-1:0] addr,
                      output bit [DATA_WIDTH-1:0] data,
                      output bit                  slverr);
        apb_transfer #(ADDR_WIDTH, DATA_WIDTH) tr;
        `uvm_create(tr)
        tr.addr  = addr;
        tr.write = 1'b0;
        `uvm_send(tr)
        data   = tr.rdata;
        slverr = tr.slverr;
    endtask

    // Read and verify
    virtual task read_check(input bit [ADDR_WIDTH-1:0] addr,
                            input bit [DATA_WIDTH-1:0] exp_data,
                            input bit [DATA_WIDTH-1:0] mask = '1,
                            input string desc = "");
        bit [DATA_WIDTH-1:0] rd_val;
        bit slverr;
        read(addr, rd_val, slverr);
        if ((rd_val & mask) !== (exp_data & mask)) begin
            `uvm_error("APB_CHK_FAIL", $sformatf("%s [APB 0x%08h] Read: 0x%08h != Exp: 0x%08h (mask: 0x%08h)",
                                                 desc, addr, rd_val, exp_data, mask))
        end else begin
            `uvm_info("APB_CHK_PASS", $sformatf("%s [APB 0x%08h] Read matched: 0x%08h", desc, addr, rd_val), UVM_HIGH)
        end
    endtask

    virtual task body();
    endtask

endclass : apb_base_seq

`endif // APB_BASE_SEQ_SV

