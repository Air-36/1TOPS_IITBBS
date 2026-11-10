class regfile_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(regfile_scoreboard)
    
    uvm_analysis_imp #(regfile_transaction, regfile_scoreboard) sb_imp;
    bit [31:0] expected_mem [1:31];
    
    function new(string name = "regfile_scoreboard", uvm_component parent = null);
        super.new(name, parent);
        sb_imp = new("sb_imp", this);
    endfunction

    function void write(regfile_transaction tx);
        bit [31:0] exp1_pre, exp2_pre, exp_dbg_pre;
        bit [31:0] exp1_post, exp2_post, exp_dbg_post;

        // Expected values before the write edge
        exp1_pre    = (tx.rd_addr1 == 0) ? 0 : expected_mem[tx.rd_addr1];
        exp2_pre    = (tx.rd_addr2 == 0) ? 0 : expected_mem[tx.rd_addr2];
        exp_dbg_pre = (tx.dbg_rd_addr == 0) ? 0 : expected_mem[tx.dbg_rd_addr];

        // Check pre-write values
        if (tx.pre_rd_data1 !== exp1_pre)
            `uvm_error("SB", "Read port 1 pre-write mismatch")
        if (tx.pre_rd_data2 !== exp2_pre)
            `uvm_error("SB", "Read port 2 pre-write mismatch")
        if (tx.pre_dbg_data !== exp_dbg_pre)
            `uvm_error("SB", "Debug port pre-write mismatch")

        //  write
        if (tx.wr_en && tx.wr_addr != 0)
            expected_mem[tx.wr_addr] = tx.wr_data;

        // Expected values after the write 
        exp1_post    = (tx.rd_addr1 == 0) ? 0 : expected_mem[tx.rd_addr1];
        exp2_post    = (tx.rd_addr2 == 0) ? 0 : expected_mem[tx.rd_addr2];
        exp_dbg_post = (tx.dbg_rd_addr == 0) ? 0 : expected_mem[tx.dbg_rd_addr];

        // Check post-write values
        if (tx.rd_data1 !== exp1_post)
            `uvm_error("SB", "Read port 1 post-write mismatch")
        if (tx.rd_data2 !== exp2_post)
            `uvm_error("SB", "Read port 2 post-write mismatch")
        if (tx.dbg_rd_data !== exp_dbg_post)
            `uvm_error("SB", "Debug port post-write mismatch")

    endfunction

endclass
