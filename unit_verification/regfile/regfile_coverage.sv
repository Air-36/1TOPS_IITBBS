class regfile_coverage extends uvm_subscriber #(regfile_transaction);
    `uvm_component_utils(regfile_coverage)

    covergroup regfile_cg;
        // Write enable coverage
        cp_wr_en: coverpoint trans.wr_en {
            bins write_enabled  = {1};
            bins write_disabled = {0};
        }

        // Write address coverage
        cp_wr_addr: coverpoint trans.wr_addr {
            bins registers[] = {[0:31]};
        }

        // Read address coverage
        cp_rd_addr1: coverpoint trans.rd_addr1 {
            bins registers[] = {[0:31]};
        }

        cp_rd_addr2: coverpoint trans.rd_addr2 {
            bins registers[] = {[0:31]};
        }

        // Debug read address coverage
        cp_dbg_addr: coverpoint trans.dbg_rd_addr {
            bins registers[] = {[0:31]};
        }

        // Same-cycle read/write address match
        cp_same_addr: coverpoint
            (trans.wr_en && trans.wr_addr == trans.rd_addr1) {
            bins match    = {1};
            bins no_match = {0};
        }

    endgroup

    regfile_transaction trans;

    function new(string name = "regfile_coverage", uvm_component parent = null);
        super.new(name, parent);
        regfile_cg = new();
    endfunction

    function void write(regfile_transaction t);
        trans = t;
        regfile_cg.sample();
    endfunction
    
    function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("COVERAGE",
        $sformatf("Functional coverage = %.2f%%", regfile_cg.get_coverage()),
        UVM_NONE)
endfunction

endclass
