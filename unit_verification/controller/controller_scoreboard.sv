class controller_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(controller_scoreboard)

    uvm_analysis_imp #(controller_transaction,controller_scoreboard) analysis_export;

    int total_tests = 0;
    int passed_tests = 0;
    int failed_tests = 0;

    function new(string name = "controller_scoreboard", uvm_component parent = null);
        super.new(name, parent);
        analysis_export = new("analysis_export", this);
    endfunction

    function logic [22:0] reference_model(input logic [31:0] instr);

        logic [2:0] ResultSrc;
        logic MemWrite, ALUSrc;
        logic RegWrite, Branch, Jump, Jalr;
        logic [1:0] ImmSrc;
        logic [3:0] ALUControl;
        logic CSRRead, CSRWrite;
        logic mretD, wfiD, ecallD, ebreakD;
        logic IllegalInstrD, FenceID;
        logic [6:0] op;
        logic [2:0] funct3;
        logic funct7b5;
        logic [4:0] rs1, rd;
        logic [11:0] funct12;
        logic [1:0] ALUOp;
        logic csr_int;

        begin
            op       = instr[6:0];
            funct3   = instr[14:12];
            funct7b5 = instr[30];
            rs1      = instr[19:15];
            rd       = instr[11:7];
            funct12  = instr[31:20];
            ResultSrc = 0;
            MemWrite = 0;
            ALUSrc = 0;
            RegWrite = 0;
            Branch = 0;
            Jump = 0;
            Jalr = 0;
            ImmSrc = 0;
            ALUControl = 0;
            CSRRead = 0;
            CSRWrite = 0;
            mretD = 0;
            wfiD = 0;
            ecallD = 0;
            ebreakD = 0;
            IllegalInstrD = 0;
            FenceID = 0;
            ALUOp = 0;
            csr_int = 0;

            // Main decoder
            case (op)
                7'b0000011: begin
                    RegWrite = 1;
                    ALUSrc = 1;
                    ResultSrc = 1;
                end

                7'b0100011: begin
                    ImmSrc = 1;
                    ALUSrc = 1;
                    MemWrite = 1;
                end

                7'b0110011: begin
                    RegWrite = 1;
                    ALUOp = 2;
                end

                7'b1100011: begin
                    Branch = 1;
                    ImmSrc = 2'b10;
                    ALUOp = 1;
                end

                7'b0010011: begin
                    RegWrite = 1;
                    ALUSrc = 1;
                    ALUOp = 2;
                end

                7'b1101111: begin
                    RegWrite = 1;
                    ImmSrc = 3;
                    ResultSrc = 2;
                    Jump = 1;
                end

                7'b1100111: begin
                    RegWrite = 1;
                    ALUSrc = 1;
                    ResultSrc = 2;
                    Jalr = 1;
                end

                7'b0010111, 7'b0110111: begin
                    RegWrite = 1;
                    ImmSrc = 0;
                    ResultSrc = 3;
                end

                7'b1110011: begin
                    if (funct3 != 0 && funct3 != 4) begin
                        RegWrite = 1;
                        ResultSrc = 4;
                        csr_int = 1;
                    end
                end
                default: begin
                end
            endcase
            
            // ALU decoder 
           case (ALUOp)
                2'b00: ALUControl = 4'b0000;
                2'b01: ALUControl = 4'b0001;
                default: begin
                      case (funct3)
                          3'b000: ALUControl = (funct7b5 && instr[5]) ? 4'b0001 : 4'b0000;
                          3'b001: ALUControl = 4'b0100;
                          3'b010: ALUControl = 4'b0101;
                          3'b011: ALUControl = 4'b0110;
                          3'b100: ALUControl = 4'b0111;
                          3'b101: ALUControl = funct7b5 ? 4'b1000 : 4'b1001;
                          3'b110: ALUControl = 4'b0011;
                          3'b111: ALUControl = 4'b0010;
                          default: ALUControl = 4'b0000;
                     endcase
                end
            endcase

            // Privileged decoder
            mretD = (op == 7'h73 && funct3 == 0 && funct12 == 12'h302 && rs1 == 0 && rd == 0);
            wfiD = (op == 7'h73 && funct3 == 0 && funct12 == 12'h105 && rs1 == 0 && rd == 0);
            ecallD = (op == 7'h73 && funct3 == 0 && funct12 == 12'h000 && rs1 == 0 && rd == 0);
            ebreakD = (op == 7'h73 && funct3 == 0 && funct12 == 12'h001 && rs1 == 0 && rd == 0);
            IllegalInstrD = ((op == 7'h73 && funct3 == 0) && !(mretD || wfiD || ecallD || ebreakD)) || (op == 7'h73 && funct3 == 4);

            // CSR control
            CSRRead = csr_int;
            CSRWrite = csr_int && !((rs1 == 0) && funct3[1]);

            // FENCE.I detection
            FenceID = (op == 7'b0001111 && funct3 == 3'b001);

            reference_model = {
                ResultSrc, MemWrite, ALUSrc,
                RegWrite, Branch, Jump, Jalr,
                ImmSrc, ALUControl,
                CSRRead, CSRWrite,
                mretD, wfiD, ecallD, ebreakD,
                IllegalInstrD, FenceID
            };
        end
    endfunction


    function void write(controller_transaction trans);
        logic [22:0] expected;
        logic [22:0] actual;

        total_tests++;

        expected = reference_model(trans.InstrD);

        actual = {
            trans.ResultSrc, trans.MemWrite, trans.ALUSrc,
            trans.RegWrite, trans.Branch, trans.Jump, trans.Jalr,
            trans.ImmSrc, trans.ALUControl,
            trans.CSRRead, trans.CSRWrite,
            trans.mretD, trans.wfiD, trans.ecallD, trans.ebreakD,
            trans.IllegalInstrD, trans.FenceID
        };

        if (actual === expected) begin
            passed_tests++;
            `uvm_info("CTRL_PASS",
                $sformatf("Instruction=%h PASS", trans.InstrD),
                UVM_LOW)
        end
        else begin
            failed_tests++;
            `uvm_error("CTRL_FAIL",
                $sformatf("Instruction=%h Expected=%h Actual=%h",
                          trans.InstrD, expected, actual))
        end
    endfunction

    function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("CTRL_REPORT",
            $sformatf("Total=%0d Passed=%0d Failed=%0d",
                      total_tests, passed_tests, failed_tests),
            UVM_NONE)

        if (failed_tests == 0 && total_tests > 0)
            `uvm_info("CTRL_STATUS", "ALL SCOREBOARD TESTS PASSED",
                      UVM_NONE)
        else
            `uvm_error("CTRL_STATUS", "SCOREBOARD TESTS FAILED")

    endfunction
endclass
