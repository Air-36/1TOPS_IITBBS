`timescale 1ns/1ps

module tb_core_torture;

    reg clk;
    reg rst_n;

    // AHB-Lite Core Signals
    wire [31:0] HADDR;
    wire [31:0] HWDATA;
    wire [ 3:0] HWSTRB;
    wire        HWRITE;
    wire [ 2:0] HSIZE;
    wire [ 2:0] HBURST;
    wire [ 3:0] HPROT;
    wire [ 1:0] HTRANS;
    wire        HMASTLOCK;
    wire [31:0] HRDATA;
    wire        HREADY;
    wire        HRESP;

    wire [31:0] PC, PCW, ALUResultW, WriteDataW, Result;
    wire        InstrRetired, TrapM, mretM;

    localparam MEM_SIZE_BYTES = 2097152;

    // Instantiate Pure CPU Core (riscv_cpu)
    riscv_cpu #(
        .RESET_PC(32'h8000_0000)
    ) dut (
        .HCLK(clk),
        .HRESETn(rst_n),
        .HADDR(HADDR),
        .HWDATA(HWDATA),
        .HWSTRB(HWSTRB),
        .HWRITE(HWRITE),
        .HSIZE(HSIZE),
        .HBURST(HBURST),
        .HPROT(HPROT),
        .HTRANS(HTRANS),
        .HMASTLOCK(HMASTLOCK),
        .HRDATA(HRDATA),
        .HREADY(HREADY),
        .HRESP(HRESP),
        .PC(PC),
        .PCW(PCW),
        .ALUResultW(ALUResultW),
        .WriteDataW(WriteDataW),
        .Result(Result),
        .MTimerInt(1'b0),
        .MSwInt(1'b0),
        .MExtInt(1'b0),
        .MTIME_CLINT(64'd0),
        .ExternalStall(1'b0),
        .InstrRetired(InstrRetired),
        .TrapM(TrapM),
        .mretM(mretM)
    );

    // Instantiate Single-Cycle AHB Synchronous RAM
    ahb_ram #(
        .BASE_ADDR(32'h8000_0000),
        .MEM_SIZE_BYTES(MEM_SIZE_BYTES),
        .DEFAULT_WAIT_STATES(0)
    ) ram_inst (
        .HCLK(clk),
        .HRESETn(rst_n),
        .HSEL(1'b1),
        .HADDR(HADDR),
        .HTRANS(HTRANS),
        .HWRITE(HWRITE),
        .HSIZE(HSIZE),
        .HWDATA(HWDATA),
        .HWSTRB(HWSTRB),
        .HREADY(HREADY),
        .HRDATA(HRDATA),
        .HREADYOUT(HREADY),
        .HRESP(HRESP)
    );

    // Clock generator (50 MHz)
    initial clk = 0;
    always #10 clk = ~clk;

    // Hex file loader & Reset sequence
    string hex_file;
    initial begin
        rst_n = 0;
        if (!$value$plusargs("HEX=%s", hex_file)) begin
            $display("[-] ERROR: No +HEX=<file.hex> argument provided!");
            $finish;
        end
        $readmemh(hex_file, ram_inst.mem);
        #45;
        rst_n = 1;
    end

    // Latched write tracking for AHB address-data phases
    reg [31:0] latched_addr;
    reg        latched_write;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            latched_addr  <= 32'h0;
            latched_write <= 1'b0;
        end else if (HREADY) begin
            latched_addr  <= HADDR;
            latched_write <= (HTRANS == 2'b10 || HTRANS == 2'b11) && HWRITE;
        end
    end

    // Metrics tracking
    integer cycle_count;
    integer instructions_retired;
    localparam MAX_CYCLES = 500000;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cycle_count          <= 0;
            instructions_retired <= 0;
        end else begin
            cycle_count <= cycle_count + 1;
            if (InstrRetired) begin
                instructions_retired <= instructions_retired + 1;
            end
        end
    end

    // Monitor completion via tohost (0x80001004)
    always @(posedge clk) begin
        if (rst_n && latched_write && HREADY) begin
            // Console streaming
            if (latched_addr == 32'h8000_1000) begin
                $write("%c", HWDATA[7:0]);
                $fflush();
            end
            // tohost status mailbox
            else if (latched_addr == 32'h8000_1004) begin
                if (HWDATA == 32'h1) begin
                    $display("\n>>> [PASS] Torture Test PASSED! <<<");
                    $display("    Cycles: %0d | Instructions: %0d | Core CPI: %0.2f\n",
                             cycle_count, instructions_retired,
                             real'(cycle_count) / real'(instructions_retired > 0 ? instructions_retired : 1));
                    $finish;
                end else begin
                    $display("\n>>> [FAIL] Torture Test FAILED! (Fail Code = 0x%08x, Subtest #%0d) <<<", 
                             HWDATA, (HWDATA >> 1));
                    $fatal(1, "Torture Test Failure detected!");
                end
            end
        end

        if (cycle_count >= MAX_CYCLES) begin
            $display("\n[-] ERROR: Torture Test TIMEOUT after %0d cycles! (PC: 0x%08x)", MAX_CYCLES, PC);
            $fatal(1, "Simulation Timeout");
        end
    end

endmodule
