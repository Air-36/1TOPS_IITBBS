class regfile_transaction extends uvm_sequence_item;
    `uvm_object_utils(regfile_transaction)

    rand bit        wr_en;
    rand bit [4:0]  wr_addr;
    rand bit [31:0] wr_data;
    rand bit [4:0]  rd_addr1;
    rand bit [4:0]  rd_addr2;
    rand bit [4:0]  dbg_rd_addr;
    bit [31:0] rd_data1;
    bit [31:0] rd_data2;
    bit [31:0] dbg_rd_data;
    bit [31:0] pre_rd_data1;
    bit [31:0] pre_rd_data2;
    bit [31:0] pre_dbg_data;

    // Constructor
    function new(string name = "regfile_transaction");
        super.new(name);
    endfunction

    // Constraints
    constraint write_enable_c {
        wr_en dist {1 := 70, 0 := 30};
    }

    constraint address_c {
        wr_addr inside {[0:31]};
        rd_addr1 inside {[0:31]};
        rd_addr2 inside {[0:31]};
        dbg_rd_addr inside {[0:31]};
    }

endclass
