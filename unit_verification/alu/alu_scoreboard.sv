class alu_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(alu_scoreboard)

    uvm_analysis_imp #(alu_transaction, alu_scoreboard) sb_imp;

    int total_tests;
    int passed_tests;
    int failed_tests;

    function new(string name = "alu_scoreboard",uvm_component parent = null);
        super.new(name, parent);
        sb_imp = new("sb_imp", this);
    endfunction

    // reference model
    function void write(alu_transaction tr);

        logic [31:0] expected_out;
        logic        expected_zero;
        logic        expected_less;
        logic        expected_less_u;

        total_tests++;

        case (tr.alu_ctrl)

            4'b0000: expected_out = tr.a + tr.b;
            4'b0001: expected_out = tr.a - tr.b;
            4'b0010: expected_out = tr.a & tr.b;
            4'b0011: expected_out = tr.a | tr.b;
            4'b0100: expected_out = tr.a << tr.b[4:0];
            4'b0101: expected_out =
                         ($signed(tr.a) < $signed(tr.b)) ? 32'd1 : 32'd0;
            4'b0110: expected_out =
                         (tr.a < tr.b) ? 32'd1 : 32'd0;
            4'b0111: expected_out = tr.a ^ tr.b;
            4'b1000: expected_out =
                         $signed(tr.a) >>> tr.b[4:0];
            4'b1001: expected_out = tr.a >> tr.b[4:0];

            default: expected_out = 'x;

        endcase

        expected_zero   = (expected_out == 0);
        expected_less   = ($signed(tr.a) < $signed(tr.b));
        expected_less_u = (tr.a < tr.b);

        if ((tr.alu_out !== expected_out) ||(tr.zero    !== expected_zero) ||(tr.less    !== expected_less) ||(tr.less_u  !== expected_less_u)) begin
            failed_tests++;
            `uvm_error("ALU_MISMATCH",
                $sformatf(
                "CTRL=%0h A=%0h B=%0h | DUT=%0h Z=%b L=%b LU=%b | EXP=%0h Z=%b L=%b LU=%b",
                tr.alu_ctrl, tr.a, tr.b,tr.alu_out, tr.zero, tr.less, tr.less_u,
                expected_out, expected_zero,expected_less, expected_less_u
                ))
        end
        else begin
            passed_tests++;

            `uvm_info("ALU_PASS",
                $sformatf("CTRL=%0h A=%0h B=%0h OUT=%0h",
                tr.alu_ctrl, tr.a, tr.b, tr.alu_out),UVM_HIGH)
        end
    endfunction

    function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("ALU_SUMMARY",
            $sformatf(
            "Total=%0d Passed=%0d Failed=%0d",
            total_tests, passed_tests, failed_tests),
            UVM_NONE)

    endfunction
endclass
