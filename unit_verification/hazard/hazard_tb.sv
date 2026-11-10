module hazard_tb;

    import uvm_pkg::*;
    import hazard_pkg::*;


    hazard_if vif();

    hazard hazard_dut (
        .Rs1D          (vif.Rs1D),
        .Rs2D          (vif.Rs2D),
        .Rs1E          (vif.Rs1E),
        .Rs2E          (vif.Rs2E),
        .RdE           (vif.RdE),
        .RdM           (vif.RdM),
        .RdW           (vif.RdW),
        .RegWriteM     (vif.RegWriteM),
        .RegWriteW     (vif.RegWriteW),
        .ResultSrcE    (vif.ResultSrcE),
        .PCSrcE        (vif.PCSrcE),
        .TrapM         (vif.TrapM),
        .mretM         (vif.mretM),
        .LSUStallM     (vif.LSUStallM),
        .IFUStallF     (vif.IFUStallF),
        .ExternalStall (vif.ExternalStall),
        .ForwardAE     (vif.ForwardAE),
        .ForwardBE     (vif.ForwardBE),
        .StallF        (vif.StallF),
        .StallD        (vif.StallD),
        .StallE        (vif.StallE),
        .StallM        (vif.StallM),
        .StallW        (vif.StallW),
        .FlushD        (vif.FlushD),
        .FlushE        (vif.FlushE),
        .FlushM        (vif.FlushM)
    );

    initial begin
        uvm_config_db #(virtual hazard_if)::set(
            null,
            "*",
            "vif",
            vif
        );
        run_test("hazard_test");
    end
endmodule
