class alu_coverage extends uvm_subscriber #(alu_transaction);

    `uvm_component_utils(alu_coverage)

    alu_transaction tr;

    covergroup alu_cg;

        // All 10 ALU operations
        cp_operation: coverpoint tr.alu_ctrl {
            bins operations[] = {[0:9]};
        }

        // Operand A categories
        cp_a: coverpoint tr.a {
            bins zero          = {32'h00000000};
            bins one           = {32'h00000001};
            bins all_ones      = {32'hFFFFFFFF};
            bins max_positive  = {32'h7FFFFFFF};
            bins min_negative  = {32'h80000000};
            bins other         = default;
        }

        // Operand B categories
        cp_b: coverpoint tr.b {
            bins zero          = {32'h00000000};
            bins one           = {32'h00000001};
            bins all_ones      = {32'hFFFFFFFF};
            bins max_positive  = {32'h7FFFFFFF};
            bins min_negative  = {32'h80000000};
            bins other         = default;
        }

        // Signed operand combinations
        cp_signs: coverpoint {tr.a[31], tr.b[31]} {
            bins pos_pos = {2'b00};
            bins pos_neg = {2'b01};
            bins neg_pos = {2'b10};
            bins neg_neg = {2'b11};
        }

        // Shift amount: low 5 bits are used by the DUT
        cp_shift: coverpoint tr.b[4:0] {
            bins shift_0  = {0};
            bins shift_1  = {1};
            bins shift_31 = {31};
        }

        // Operation versus operand category
        operation_a_cross: cross cp_operation, cp_a;

        operation_b_cross: cross cp_operation, cp_b;

    endgroup

    function new(string name = "alu_coverage",
                 uvm_component parent = null);
        super.new(name, parent);
        alu_cg = new();
    endfunction

    function void write(alu_transaction t);
        tr = t;
        alu_cg.sample();
    endfunction

    function void report_phase(uvm_phase phase);
        super.report_phase(phase);

        `uvm_info("ALU_COV",
            $sformatf("Functional Coverage = %0.2f%%",
                      alu_cg.get_coverage()),
            UVM_NONE)
    endfunction

endclass
