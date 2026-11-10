class regfile_sequence extends uvm_sequence #(regfile_transaction);
    `uvm_object_utils(regfile_sequence)

    function new(string name = "regfile_sequence");
        super.new(name);
    endfunction

    task body();
        regfile_transaction tx;

        // Initialize all registers x1-x31
        for (int i = 1; i < 32; i++) begin
            tx = regfile_transaction::type_id::create("tx");
            start_item(tx);
            tx.wr_en       = 1;
            tx.wr_addr     = i;
            tx.wr_data     = 32'h1000_0000 + i;
            tx.rd_addr1    = 0;
            tx.rd_addr2    = 0;
            tx.dbg_rd_addr = 0;
            finish_item(tx);
        end
        
        // Randomized read/write testing
        repeat (200) begin
            tx = regfile_transaction::type_id::create("tx");
            start_item(tx);
            if (!tx.randomize())
                `uvm_fatal("RAND_FAIL","Register file transaction randomization failed")
            finish_item(tx);
        end
        
        // x0 write protection
        tx = regfile_transaction::type_id::create("tx");
        start_item(tx);
        tx.wr_en       = 1;
        tx.wr_addr     = 0;
        tx.wr_data     = 32'hDEAD_BEEF;
        tx.rd_addr1    = 0;
        tx.rd_addr2    = 0;
        tx.dbg_rd_addr = 0;
        finish_item(tx);
        
        // Same-cycle read/write to x5
        tx = regfile_transaction::type_id::create("tx");
        start_item(tx);
        tx.wr_en       = 1;
        tx.wr_addr     = 5;
        tx.wr_data     = 32'h5678_9ABC;
        tx.rd_addr1    = 5;
        tx.rd_addr2    = 5;
        tx.dbg_rd_addr = 5;
        finish_item(tx);

        // Verify updated x5
        tx = regfile_transaction::type_id::create("tx");
        start_item(tx);
        tx.wr_en       = 0;
        tx.wr_addr     = 0;
        tx.wr_data     = 0;
        tx.rd_addr1    = 5;
        tx.rd_addr2    = 5;
        tx.dbg_rd_addr = 5;
        finish_item(tx);
       
    endtask
endclass
