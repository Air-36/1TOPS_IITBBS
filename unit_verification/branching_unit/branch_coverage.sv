class branch_coverage extends uvm_subscriber #(branch_transaction);
    `uvm_component_utils(branch_coverage)

    covergroup branch_cg with function sample(
        bit [2:0] funct3,
        bit       Zero,
        bit       Less,
        bit       LessU
    );

        // Branch instruction coverage
        cp_funct3: coverpoint funct3 {
            bins beq  = {3'b000};
            bins bne  = {3'b001};
            bins blt  = {3'b100};
            bins bge  = {3'b101};
            bins bltu = {3'b110};
            bins bgeu = {3'b111};
            bins invalid = {3'b010, 3'b011};
        }

        // Comparison flag coverage
        cp_zero: coverpoint Zero {
            bins zero_0 = {0};
            bins zero_1 = {1};
        }

        cp_less: coverpoint Less {
            bins less_0 = {0};
            bins less_1 = {1};
        }

        cp_lessu: coverpoint LessU {
            bins lessu_0 = {0};
            bins lessu_1 = {1};
        }

        // Cross coverage of instruction and comparison flags
        branch_cross: cross cp_funct3, cp_zero, cp_less, cp_lessu;

    endgroup

    function new(string name = "branch_coverage", uvm_component parent = null);
        super.new(name, parent);
        branch_cg = new();
    endfunction

    function void write(branch_transaction t);
        branch_cg.sample(
            t.funct3,
            t.Zero,
            t.Less,
            t.LessU
        );
    endfunction

    function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("COVERAGE",
            $sformatf("Branch functional coverage = %0.2f%%",
                      branch_cg.get_coverage()),
            UVM_NONE)
    endfunction

endclass

