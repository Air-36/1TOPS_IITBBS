class branch_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(branch_scoreboard)
    
    uvm_analysis_imp #(branch_transaction, branch_scoreboard) sb_imp;
    int total_count;
    int pass_count;
    int fail_count;

    function new(string name = "branch_scoreboard", uvm_component parent = null);
        super.new(name, parent);
        sb_imp = new("sb_imp", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        total_count = 0;
        pass_count  = 0;
        fail_count  = 0;
    endfunction

    function void write(branch_transaction tx);
        bit expected_branch;
        case (tx.funct3)
            3'b000: expected_branch =  tx.Zero;
            3'b001: expected_branch = !tx.Zero;
            3'b100: expected_branch =  tx.Less;
            3'b101: expected_branch = !tx.Less;
            3'b110: expected_branch =  tx.LessU;
            3'b111: expected_branch = !tx.LessU;
            default: expected_branch = 1'b0;
        endcase
        total_count++;
        if (tx.Branch === expected_branch) begin
            pass_count++;
            `uvm_info("SB",
                $sformatf("PASS: funct3=%b Zero=%b Less=%b LessU=%b Branch=%b",
                tx.funct3, tx.Zero, tx.Less, tx.LessU, tx.Branch),
                UVM_MEDIUM)
        end
        else begin
            fail_count++;
            `uvm_error("SB",
                $sformatf("FAIL: funct3=%b Zero=%b Less=%b LessU=%b Expected=%b Actual=%b",
                tx.funct3, tx.Zero, tx.Less, tx.LessU,
                expected_branch, tx.Branch))
        end
    endfunction

    function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("SB",
            $sformatf("Total=%0d PASS=%0d FAIL=%0d",
            total_count, pass_count, fail_count),
            UVM_NONE)
    endfunction
endclass

