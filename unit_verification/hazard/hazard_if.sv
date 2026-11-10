interface hazard_if;

    logic [4:0] Rs1D;
    logic [4:0] Rs2D;
    logic [4:0] Rs1E;
    logic [4:0] Rs2E;
    logic [4:0] RdE;
    logic [4:0] RdM;
    logic [4:0] RdW;
    logic RegWriteM;
    logic RegWriteW;
    logic [2:0] ResultSrcE;
    logic PCSrcE;
    logic TrapM;
    logic mretM;
    logic LSUStallM;
    logic IFUStallF;
    logic ExternalStall;
    logic [1:0] ForwardAE;
    logic [1:0] ForwardBE;
    logic StallF;
    logic StallD;
    logic StallE;
    logic StallM;
    logic StallW;
    logic FlushD;
    logic FlushE;
    logic FlushM;
    
endinterface
