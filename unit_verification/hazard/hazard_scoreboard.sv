class hazard_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(hazard_scoreboard)

    uvm_analysis_imp #(hazard_transaction, hazard_scoreboard) sb_imp;
    int total_transactions = 0;
    int passed_transactions = 0;
    int failed_transactions = 0;

    function new(string name = "hazard_scoreboard", uvm_component parent = null);
        super.new(name, parent);
        sb_imp = new("sb_imp", this);
    endfunction

    function void write(hazard_transaction tr);
        bit [1:0] exp_ForwardAE;
        bit [1:0] exp_ForwardBE;
        bit exp_StallF;
        bit exp_StallD;
        bit exp_StallE;
        bit exp_StallM;
        bit exp_StallW;
        bit exp_FlushD;
        bit exp_FlushE;
        bit exp_FlushM;
        bit lwStall;
        bit FlushCause;
        bit transaction_pass;

        total_transactions++;

        // ForwardAE: RS1 forwarding
        if ((tr.Rs1E == tr.RdM) && tr.RegWriteM && (tr.Rs1E != 5'd0))
            exp_ForwardAE = 2'b10;
        else if ((tr.Rs1E == tr.RdW) && tr.RegWriteW && (tr.Rs1E != 5'd0))
            exp_ForwardAE = 2'b01;
        else
            exp_ForwardAE = 2'b00;

        // ForwardBE: RS2 forwarding
        if ((tr.Rs2E == tr.RdM) && tr.RegWriteM && (tr.Rs2E != 5'd0))
            exp_ForwardBE = 2'b10;
        else if ((tr.Rs2E == tr.RdW) && tr.RegWriteW && (tr.Rs2E != 5'd0))
            exp_ForwardBE = 2'b01;
        else
            exp_ForwardBE = 2'b00;

        lwStall = (tr.ResultSrcE == 3'b001) && ((tr.Rs1D == tr.RdE) || (tr.Rs2D == tr.RdE)) && (tr.RdE != 5'd0);
        FlushCause = tr.PCSrcE || tr.TrapM || tr.mretM;
        exp_StallW = tr.LSUStallM | tr.ExternalStall;
        exp_StallM = tr.LSUStallM | tr.ExternalStall;
        exp_StallE = tr.LSUStallM | tr.ExternalStall;
        exp_StallD = tr.LSUStallM | (lwStall & ~FlushCause) | tr.ExternalStall;
        exp_StallF = tr.LSUStallM | ((tr.IFUStallF | lwStall) & ~FlushCause) | tr.ExternalStall;
        exp_FlushD = (!tr.LSUStallM) && (!tr.ExternalStall) && FlushCause;
        exp_FlushE = (!tr.LSUStallM) && (!tr.ExternalStall) && (lwStall || FlushCause);
        exp_FlushM = (!tr.LSUStallM) && (!tr.ExternalStall) && (tr.TrapM || tr.mretM);
        transaction_pass = 1'b1;

        if (tr.ForwardAE !== exp_ForwardAE) begin
            `uvm_error("SCOREBOARD",
                $sformatf("ForwardAE mismatch: Expected=%b Actual=%b", exp_ForwardAE, tr.ForwardAE))
            transaction_pass = 1'b0;
        end

        if (tr.ForwardBE !== exp_ForwardBE) begin
            `uvm_error("SCOREBOARD",
                $sformatf("ForwardBE mismatch: Expected=%b Actual=%b", exp_ForwardBE, tr.ForwardBE))
            transaction_pass = 1'b0;
        end

        if (tr.StallF !== exp_StallF) begin
            `uvm_error("SCOREBOARD",
                $sformatf("StallF mismatch: Expected=%b Actual=%b", exp_StallF, tr.StallF))
            transaction_pass = 1'b0;
        end

        if (tr.StallD !== exp_StallD) begin
            `uvm_error("SCOREBOARD",
                $sformatf("StallD mismatch: Expected=%b Actual=%b", exp_StallD, tr.StallD))
            transaction_pass = 1'b0;
        end

        if (tr.StallE !== exp_StallE) begin
            `uvm_error("SCOREBOARD",
                $sformatf("StallE mismatch: Expected=%b Actual=%b", exp_StallE, tr.StallE))
            transaction_pass = 1'b0;
        end

        if (tr.StallM !== exp_StallM) begin
            `uvm_error("SCOREBOARD",
                $sformatf("StallM mismatch: Expected=%b Actual=%b", exp_StallM, tr.StallM))
            transaction_pass = 1'b0;
        end

        if (tr.StallW !== exp_StallW) begin
            `uvm_error("SCOREBOARD",
                $sformatf("StallW mismatch: Expected=%b Actual=%b", exp_StallW, tr.StallW))
            transaction_pass = 1'b0;
        end

        if (tr.FlushD !== exp_FlushD) begin
            `uvm_error("SCOREBOARD",
                $sformatf("FlushD mismatch: Expected=%b Actual=%b", exp_FlushD, tr.FlushD))
            transaction_pass = 1'b0;
        end

        if (tr.FlushE !== exp_FlushE) begin
            `uvm_error("SCOREBOARD",
                $sformatf("FlushE mismatch: Expected=%b Actual=%b", exp_FlushE, tr.FlushE))
            transaction_pass = 1'b0;
        end

        if (tr.FlushM !== exp_FlushM) begin
            `uvm_error("SCOREBOARD",
                $sformatf("FlushM mismatch: Expected=%b Actual=%b", exp_FlushM, tr.FlushM))
            transaction_pass = 1'b0;
        end

        if (transaction_pass) begin
            passed_transactions++;
            `uvm_info("SCOREBOARD",
                $sformatf("Transaction %0d PASSED", total_transactions), UVM_MEDIUM)
        end
        else begin
            failed_transactions++;
        end

    endfunction

    function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("SCOREBOARD",
            $sformatf("Total=%0d Passed=%0d Failed=%0d", total_transactions, passed_transactions, failed_transactions), UVM_NONE)
    endfunction
endclass
