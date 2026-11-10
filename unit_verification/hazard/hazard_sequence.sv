class hazard_sequence extends uvm_sequence #(hazard_transaction);
    `uvm_object_utils(hazard_sequence)

    function new(string name = "hazard_sequence");
        super.new(name);
    endfunction

    task body();
        hazard_transaction req;

        // ALU-to-use: RS1 forwarding from Memory
        req = hazard_transaction::type_id::create("req");
        start_item(req);
        req.Rs1E = 5'd5;
        req.RdM = 5'd5;
        req.RegWriteM = 1'b1;
        finish_item(req);

        // ALU-to-use: RS2 forwarding from Memory
        req = hazard_transaction::type_id::create("req");
        start_item(req);
        req.Rs2E = 5'd6;
        req.RdM = 5'd6;
        req.RegWriteM = 1'b1;
        finish_item(req);

        // ALU-to-use: Both operands from Memory
        req = hazard_transaction::type_id::create("req");
        start_item(req);
        req.Rs1E = 5'd7;
        req.Rs2E = 5'd7;
        req.RdM = 5'd7;
        req.RegWriteM = 1'b1;
        finish_item(req);

        // ALU-to-use: RS1 forwarding from Writeback
        req = hazard_transaction::type_id::create("req");
        start_item(req);
        req.Rs1E = 5'd8;
        req.RdW = 5'd8;
        req.RegWriteW = 1'b1;
        finish_item(req);

        // ALU-to-use: RS2 forwarding from Writeback
        req = hazard_transaction::type_id::create("req");
        start_item(req);
        req.Rs2E = 5'd9;
        req.RdW = 5'd9;
        req.RegWriteW = 1'b1;
        finish_item(req);

        // Forwarding priority: Memory over Writeback
        req = hazard_transaction::type_id::create("req");
        start_item(req);
        req.Rs1E = 5'd10;
        req.RdM = 5'd10;
        req.RdW = 5'd10;
        req.RegWriteM = 1'b1;
        req.RegWriteW = 1'b1;
        finish_item(req);

        // LOAD-to-use: RS1 dependency
        req = hazard_transaction::type_id::create("req");
        start_item(req);
        req.Rs1D = 5'd11;
        req.RdE = 5'd11;
        req.ResultSrcE = 3'b001;
        finish_item(req);

        // LOAD-to-use: RS2 dependency
        req = hazard_transaction::type_id::create("req");
        start_item(req);
        req.Rs2D = 5'd12;
        req.RdE = 5'd12;
        req.ResultSrcE = 3'b001;
        finish_item(req);

        // LOAD-to-use: Both operands dependent
        req = hazard_transaction::type_id::create("req");
        start_item(req);
        req.Rs1D = 5'd13;
        req.Rs2D = 5'd13;
        req.RdE = 5'd13;
        req.ResultSrcE = 3'b001;
        finish_item(req);

        // STORE-to-use: Store data depends on load result
        req = hazard_transaction::type_id::create("req");
        start_item(req);
        req.Rs2D = 5'd14;
        req.RdE = 5'd14;
        req.ResultSrcE = 3'b001;
        finish_item(req);

        // No load-use dependency
        req = hazard_transaction::type_id::create("req");
        start_item(req);
        req.Rs1D = 5'd15;
        req.Rs2D = 5'd16;
        req.RdE = 5'd17;
        req.ResultSrcE = 3'b001;
        finish_item(req);

        // x0 must not cause a load-use stall
        req = hazard_transaction::type_id::create("req");
        start_item(req);
        req.Rs1D = 5'd0;
        req.Rs2D = 5'd0;
        req.RdE = 5'd0;
        req.ResultSrcE = 3'b001;
        finish_item(req);

    endtask
endclass
