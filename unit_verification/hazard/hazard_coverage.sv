class hazard_coverage extends uvm_subscriber #(hazard_transaction);
    `uvm_component_utils(hazard_coverage)

    int sample_count = 0;

    covergroup hazard_cg;

        // Forwarding selections
        cp_forward_a: coverpoint item.ForwardAE {
            bins no_forward = {2'b00};
            bins from_wb    = {2'b01};
            bins from_mem   = {2'b10};
        }

        cp_forward_b: coverpoint item.ForwardBE {
            bins no_forward = {2'b00};
            bins from_wb    = {2'b01};
            bins from_mem   = {2'b10};
        }

        // Decode-stage operand dependency
        cp_rs1_hazard: coverpoint
            (item.Rs1D == item.RdE && item.RdE != 0) {
            bins no_hazard = {0};
            bins hazard    = {1};
        }

        cp_rs2_hazard: coverpoint
            (item.Rs2D == item.RdE && item.RdE != 0) {
            bins no_hazard = {0};
            bins hazard    = {1};
        }

        cp_both_operands: coverpoint
            ((item.Rs1D == item.RdE) &&
             (item.Rs2D == item.RdE) &&
             (item.RdE != 0)) {
            bins not_both = {0};
            bins both     = {1};
        }

        // Load-use condition
        cp_load_use: coverpoint
            (item.ResultSrcE == 3'b001) {
            bins non_load = {0};
            bins load     = {1};
        }

        // Stall and flush behavior
        cp_stall_f: coverpoint item.StallF {
            bins no_stall = {0};
            bins stall    = {1};
        }

        cp_stall_d: coverpoint item.StallD {
            bins no_stall = {0};
            bins stall    = {1};
        }

        cp_flush_e: coverpoint item.FlushE {
            bins no_flush = {0};
            bins flush    = {1};
        }

        // Operand dependency combinations
        operand_cross: cross cp_rs1_hazard, cp_rs2_hazard;

    endgroup

    hazard_transaction item;

    function new(string name = "hazard_coverage", uvm_component parent = null);
        super.new(name, parent);
        hazard_cg = new();
    endfunction

    function void write(hazard_transaction t);
        item = t;
        hazard_cg.sample();
        sample_count++;
    endfunction

    function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("COVERAGE",
            $sformatf("Hazard coverage: %0.2f%% | Samples: %0d",
                      hazard_cg.get_coverage(),
                      sample_count),
            UVM_NONE)
    endfunction
endclass
