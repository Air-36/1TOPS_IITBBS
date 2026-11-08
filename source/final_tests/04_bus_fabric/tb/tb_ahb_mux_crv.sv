`timescale 1ns/1ps

// =============================================================================
// Testbench: tb_ahb_mux_crv.sv
// Purpose: Class-Based Constrained-Random Verification (CRV) for 2-Master
//          AHB-Lite Bus Arbiter and Multiplexer (ahb_mux.sv)
// =============================================================================

module tb_ahb_mux_crv;

    reg         HCLK;
    reg         HRESETn;
    reg         core_halt;

    // Master 0 (CPU)
    reg  [31:0] M0_HADDR;
    reg  [31:0] M0_HWDATA;
    reg         M0_HWRITE;
    reg  [ 1:0] M0_HTRANS;
    reg  [ 2:0] M0_HSIZE;
    wire [31:0] M0_HRDATA;
    wire        M0_HREADY;
    wire        M0_HRESP;

    // Master 1 (Debugger)
    reg  [31:0] M1_HADDR;
    reg  [31:0] M1_HWDATA;
    reg         M1_HWRITE;
    reg  [ 1:0] M1_HTRANS;
    reg  [ 2:0] M1_HSIZE;
    wire [31:0] M1_HRDATA;
    wire        M1_HREADY;
    wire        M1_HRESP;

    // Slave Interconnect
    wire [31:0] S_HADDR;
    wire [31:0] S_HWDATA;
    wire        S_HWRITE;
    wire [ 1:0] S_HTRANS;
    wire [ 2:0] S_HSIZE;
    wire [ 2:0] S_HBURST;
    wire [ 3:0] S_HPROT;
    wire        S_HMASTLOCK;
    reg  [31:0] S_HRDATA;
    reg         S_HREADY;
    reg         S_HRESP;

    // Clock generator (50 MHz)
    initial HCLK = 0;
    always #10 HCLK = ~HCLK;

    // DUT Instantiation
    ahb_mux #(
        .ADDR_WIDTH(32),
        .DATA_WIDTH(32)
    ) dut (
        .HCLK(HCLK),
        .HRESETn(HRESETn),

        // M0
        .M0_HADDR(M0_HADDR),
        .M0_HWDATA(M0_HWDATA),
        .M0_HWRITE(M0_HWRITE),
        .M0_HTRANS(M0_HTRANS),
        .M0_HSIZE(M0_HSIZE),
        .M0_HBURST(3'b000),
        .M0_HPROT(4'b0011),
        .M0_HMASTLOCK(1'b0),
        .M0_HRDATA(M0_HRDATA),
        .M0_HREADY(M0_HREADY),
        .M0_HRESP(M0_HRESP),

        // M1
        .M1_HADDR(M1_HADDR),
        .M1_HWDATA(M1_HWDATA),
        .M1_HWRITE(M1_HWRITE),
        .M1_HTRANS(M1_HTRANS),
        .M1_HSIZE(M1_HSIZE),
        .M1_HBURST(3'b000),
        .M1_HPROT(4'b0011),
        .M1_HMASTLOCK(1'b0),
        .M1_HRDATA(M1_HRDATA),
        .M1_HREADY(M1_HREADY),
        .M1_HRESP(M1_HRESP),

        // S
        .S_HADDR(S_HADDR),
        .S_HWDATA(S_HWDATA),
        .S_HWRITE(S_HWRITE),
        .S_HTRANS(S_HTRANS),
        .S_HSIZE(S_HSIZE),
        .S_HBURST(S_HBURST),
        .S_HPROT(S_HPROT),
        .S_HMASTLOCK(S_HMASTLOCK),
        .S_HRDATA(S_HRDATA),
        .S_HREADY(S_HREADY),
        .S_HRESP(S_HRESP)
    );

    // -------------------------------------------------------------------------
    // Transaction Class
    // -------------------------------------------------------------------------
    class ahb_trans;
        bit [31:0] addr;
        bit [31:0] data;
        bit        write;
        bit [ 2:0] size;
        bit [ 1:0] trans;

        function void randomize_data();
            addr  = ($urandom_range(0, 63) << 2);
            data  = $urandom();
            write = $urandom_range(0, 1);
            size  = 3'b010;
            trans = 2'b10;
        endfunction
    endclass

    integer verified_trans_count = 0;
    integer errors = 0;

    // Simple slave memory model
    reg [31:0] slave_mem [0:255];
    reg [31:0] latched_addr;
    reg        latched_write;
    reg        latched_active;

    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            latched_addr   <= 32'd0;
            latched_write  <= 1'b0;
            latched_active <= 1'b0;
            S_HRDATA       <= 32'd0;
        end else if (S_HREADY) begin
            if (latched_active && latched_write) begin
                slave_mem[latched_addr[9:2]] <= S_HWDATA;
            end

            latched_active <= (S_HTRANS == 2'b10);
            latched_write  <= S_HWRITE;
            latched_addr   <= S_HADDR;

            if (S_HTRANS == 2'b10 && !S_HWRITE) begin
                S_HRDATA <= slave_mem[S_HADDR[9:2]];
            end
        end
    end

    // Test Scenario Execution
    initial begin
        ahb_trans tr;
        $display("=== Running Constrained-Random Bus Fabric Verification: ahb_mux.sv ===");

        HRESETn   = 1'b0;
        core_halt = 1'b0;
        M0_HTRANS = 2'b00;
        M1_HTRANS = 2'b00;
        S_HREADY  = 1'b1;
        S_HRESP   = 1'b0;

        repeat (5) @(posedge HCLK);
        HRESETn = 1'b1;
        @(posedge HCLK);

        // Preload slave memory
        for (int i = 0; i < 256; i++) slave_mem[i] = 32'hA000_0000 + i;

        // ---------------------------------------------------------------------
        // TEST 1: Uncontended Master 0 (CPU) Transfers
        // ---------------------------------------------------------------------
        // All checks use ports only (no dut.* hierarchical references), so the
        // test works with any ahb_mux implementation. Masters are AHB-Lite
        // compliant: a request is held until that master sees HREADY = 1.
        // ---------------------------------------------------------------------

        // ---------------------------------------------------------------------
        // TEST 1: Uncontended Master 0 (Core) Transfers
        // ---------------------------------------------------------------------
        $display("[TEST 1] Testing uncontended Master 0 transactions...");
        for (int t = 0; t < 20; t++) begin
            tr = new();
            tr.randomize_data();
            @(posedge HCLK); #1;
            M0_HADDR = tr.addr; M0_HWRITE = tr.write; M0_HTRANS = tr.trans; M0_HSIZE = tr.size;
            #1; while (!M0_HREADY) begin @(posedge HCLK); #1; end
            // Accepted by M0 -> must be the transfer on the slave bus this cycle
            if (S_HTRANS !== 2'b10 || S_HADDR !== tr.addr || S_HWRITE !== tr.write) begin
                $display("[FAIL] Master 0 accepted 0x%08x but slave bus shows HTRANS=%b HADDR=0x%08x", tr.addr, S_HTRANS, S_HADDR);
                errors++;
            end
            @(posedge HCLK); #1;
            M0_HTRANS = 2'b00; M0_HWDATA = tr.data;            // data phase
            while (!M0_HREADY) begin @(posedge HCLK); #1; end
            verified_trans_count++;
        end
        $display("[TEST 1] done: Master 0 executed 20 transactions.");

        // ---------------------------------------------------------------------
        // TEST 2: Uncontended Master 1 (Debugger) Transfers
        // ---------------------------------------------------------------------
        $display("\n[TEST 2] Testing uncontended Master 1 (Debugger) transactions...");
        for (int t = 0; t < 20; t++) begin
            tr = new();
            tr.randomize_data();
            @(posedge HCLK); #1;
            M1_HADDR = tr.addr; M1_HWRITE = tr.write; M1_HTRANS = tr.trans; M1_HSIZE = tr.size;
            #1; while (!M1_HREADY) begin @(posedge HCLK); #1; end
            if (S_HTRANS !== 2'b10 || S_HADDR !== tr.addr || S_HWRITE !== tr.write) begin
                $display("[FAIL] Master 1 accepted 0x%08x but slave bus shows HTRANS=%b HADDR=0x%08x", tr.addr, S_HTRANS, S_HADDR);
                errors++;
            end
            @(posedge HCLK); #1;
            M1_HTRANS = 2'b00; M1_HWDATA = tr.data;
            while (!M1_HREADY) begin @(posedge HCLK); #1; end
            verified_trans_count++;
        end
        $display("[TEST 2] done: Master 1 executed 20 transactions.");

        // ---------------------------------------------------------------------
        // TEST 3: Simultaneous Contention
        // Both masters request in the same cycle. Checks (ports only):
        //   - the debugger's (M1) address reaches the slave first (priority)
        //   - BOTH transfers reach the slave exactly once (nothing lost)
        // ---------------------------------------------------------------------
        $display("\n[TEST 3] Testing simultaneous bus contention (M0 vs M1)...");
        for (int t = 0; t < 20; t++) begin
            bit m0_done, m1_done;
            int seen_m0, seen_m1, first;      // first: 0 = none yet, 1 = M1 first, 2 = M0 first
            @(posedge HCLK); #1;
            M0_HADDR = 32'h0000_0100 + (t * 4); M0_HWRITE = 1'b0; M0_HTRANS = 2'b10;
            M1_HADDR = 32'h0000_0200 + (t * 4); M1_HWRITE = 1'b0; M1_HTRANS = 2'b10;
            m0_done = 0; m1_done = 0; seen_m0 = 0; seen_m1 = 0; first = 0;
            for (int c = 0; c < 10; c++) begin
                #1;
                // slave-side acceptance this cycle
                if (S_HTRANS[1] && S_HREADY) begin
                    if (S_HADDR === M0_HADDR) begin seen_m0++; if (first == 0) first = 2; end
                    if (S_HADDR === M1_HADDR) begin seen_m1++; if (first == 0) first = 1; end
                end
                // master-side acceptance this cycle -> drop the request after this edge
                if (M0_HTRANS[1] && M0_HREADY) m0_done = 1;
                if (M1_HTRANS[1] && M1_HREADY) m1_done = 1;
                @(posedge HCLK); #1;
                if (m0_done) M0_HTRANS = 2'b00;
                if (m1_done) M1_HTRANS = 2'b00;
            end
            if (first != 1) begin
                $display("[FAIL] Contention %0d: debugger was not first on the slave bus (first=%s)", t, first == 2 ? "M0" : "none");
                errors++;
            end
            if (seen_m0 != 1 || seen_m1 != 1) begin
                $display("[FAIL] Contention %0d: slave saw M0 %0d time(s), M1 %0d time(s) (expected 1 each)", t, seen_m0, seen_m1);
                errors++;
            end
            verified_trans_count++;
        end
        $display("[TEST 3] done: 20 contention rounds checked.");

        // ---------------------------------------------------------------------
        // TEST 4: Debugger write is committed to the slave
        // (the old test set core_halt, which is not a port of ahb_mux, so it
        //  had no effect; the check below is the same write check, done
        //  AHB-compliantly)
        // ---------------------------------------------------------------------
        $display("\n[TEST 4] Testing debugger write commit...");
        @(posedge HCLK); #1;
        M1_HADDR = 32'h0000_0000; M1_HWRITE = 1'b1; M1_HTRANS = 2'b10;
        #1; while (!M1_HREADY) begin @(posedge HCLK); #1; end
        @(posedge HCLK); #1;
        M1_HTRANS = 2'b00; M1_HWDATA = 32'hBEEF_CAFE;           // data phase
        while (!M1_HREADY) begin @(posedge HCLK); #1; end
        @(posedge HCLK); #1;                                     // slave commits at this edge
        if (slave_mem[0] !== 32'hBEEF_CAFE) begin
            $display("[FAIL] Write data not committed to slave! (got 0x%08x, exp 0xBEEF_CAFE)", slave_mem[0]);
            errors++;
        end else begin
            $display("[TEST 4] PASSED: Debugger wrote memory.");
        end

        // ---------------------------------------------------------------------
        // Final Summary
        // ---------------------------------------------------------------------
        if (errors == 0) begin
            $display("\n==================================================================");
            $display(" [TB Result] PASSED: %0d Constrained-Random Bus Transfers Verified!", verified_trans_count);
            $display("==================================================================\n");
        end else begin
            $display("\n[TB Result] FAILED with %0d errors!\n", errors);
        end

        $finish;
    end

endmodule
