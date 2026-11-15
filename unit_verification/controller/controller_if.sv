interface controller_if;

    logic [31:0] InstrD;
    logic [2:0] ResultSrc;
    logic MemWrite;
    logic ALUSrc;
    logic RegWrite;
    logic Branch;
    logic Jump;
    logic Jalr;
    logic [1:0] ImmSrc;
    logic [3:0] ALUControl;
    logic CSRRead;
    logic CSRWrite;
    logic mretD;
    logic wfiD;
    logic ecallD;
    logic ebreakD;
    logic IllegalInstrD;
    logic FenceID;
    bit sample_req = 0;
    bit sample_ack = 0;
    
endinterface
