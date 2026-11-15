module controller_top;

    import uvm_pkg::*;
    import controller_pkg::*;
    
    controller_if intf();

    controller dut (
        .InstrD       (intf.InstrD),
        .ResultSrc    (intf.ResultSrc),
        .MemWrite     (intf.MemWrite),
        .ALUSrc       (intf.ALUSrc),
        .RegWrite     (intf.RegWrite),
        .Branch       (intf.Branch),
        .Jump         (intf.Jump),
        .Jalr         (intf.Jalr),
        .ImmSrc       (intf.ImmSrc),
        .ALUControl   (intf.ALUControl),
        .CSRRead      (intf.CSRRead),
        .CSRWrite     (intf.CSRWrite),
        .mretD        (intf.mretD),
        .wfiD         (intf.wfiD),
        .ecallD       (intf.ecallD),
        .ebreakD      (intf.ebreakD),
        .IllegalInstrD(intf.IllegalInstrD),
        .FenceID      (intf.FenceID)
    );

    initial begin
        uvm_config_db#(virtual controller_if)::set(null, "*", "vif", intf);
        run_test("controller_test");
    end

endmodule
