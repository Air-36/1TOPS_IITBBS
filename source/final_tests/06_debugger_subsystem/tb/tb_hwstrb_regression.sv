`timescale 1ns/1ps

// =============================================================================
// Testbench: tb_hwstrb_regression.sv
// Purpose: Regression testbench verifying HWSTRB bus ownership & strobe timing
//
// Tests:
//   T1: Core Store Interrupted by Halt on Store Data Cycle
//   T2 (running): Debugger writes while CPU core is running
//   T2 (halted by pin): Debugger writes while CPU core is halted by pin
//   T2 (halted by C command): Debugger writes while CPU core is halted by ADP 'C 0202'
// =============================================================================

module tb_hwstrb_regression;

    localparam CLK_FREQ    = 50_000_000;
    localparam BAUD_RATE   = 2_500_000;
    localparam BIT_PERIOD  = 1_000_000_000 / BAUD_RATE; // 400 ns per bit

    reg clk;
    reg reset;

    initial clk = 0;
    always #10 clk = ~clk; // 50 MHz (20 ns period)

    // Watchdog
    initial begin
        #10000000; // 10 ms timeout
        $display("\n[ERROR] Simulation timeout in tb_hwstrb_regression!");
        $finish;
    end

    wire [31:0] PCW, ResultW;
    wire [31:0] GPIOOUT, GPIOEN;
    wire        UARTSout;
    wire        core_halted_led;

    reg         dbg_sel;
    reg         uart_rx;
    wire        uart_tx;

    // Instantiate SoC
    riscv_soc_ahb #(
        .RESET_PC        (32'h8000_0000),
        .MEM_SIZE_BYTES  (16384),
        .CLK_FREQ        (CLK_FREQ),
        .BAUD_RATE       (BAUD_RATE)
    ) soc (
        .clk             (clk),
        .reset           (reset),
        .MExtInt         (1'b0),
        .TrapM           (),
        .mretM           (),
        .PCW             (PCW),
        .ResultW         (ResultW),
        .GPIOIN          (32'h0),
        .GPIOOUT         (GPIOOUT),
        .GPIOEN          (GPIOEN),
        .UARTSin         (1'b1),
        .UARTSout        (UARTSout),
        .dbg_sel         (dbg_sel),
        .uart_rx         (uart_rx),
        .uart_tx         (uart_tx),
        .ft1248_clk      (),
        .ft1248_ss_n     (),
        .ft1248_miso     (1'b1),
        .ft1248_miosio   (),
        .core_halted_led (core_halted_led),
        .SPIIn           (1'b0),
        .SPIOut          (),
        .SPICS           (),
        .SPICLK          ()
    );

    // -------------------------------------------------------------------------
    // UART Drivers
    // -------------------------------------------------------------------------
    task send_uart_byte(input [7:0] data);
        integer i;
        begin
            uart_rx = 1'b0; // Start bit
            #(BIT_PERIOD);
            for (i = 0; i < 8; i = i + 1) begin
                uart_rx = data[i];
                #(BIT_PERIOD);
            end
            uart_rx = 1'b1; // Stop bit
            #(BIT_PERIOD);
            #(BIT_PERIOD / 2);
        end
    endtask

    task send_uart_string(input string str);
        integer j;
        begin
            for (j = 0; j < str.len(); j = j + 1) begin
                send_uart_byte(str[j]);
            end
        end
    endtask

    task wait_for_prompt;
        begin
            wait (soc.u_debugger.u_socdebug_ahb.u_adp_control.adp_state == 6'd15);
            wait (soc.u_debugger.u_uart.tx_state == 2'd0 && !soc.u_debugger.u_uart.s_axis_tvalid);
            #(BIT_PERIOD * 4);
        end
    endtask

    // -------------------------------------------------------------------------
    // Program Memory Initialization
    // -------------------------------------------------------------------------
    task load_program;
        integer i;
        begin
            for (i = 0; i < 2048; i = i + 1) begin
                soc.uncore.ram_i.mem[i] = 32'h0000_0013; // nop
                soc.uncore.ram_d.mem[i] = 32'h0000_0000;
            end
            // Instruction 0: addi x1, x0, 0x2a -> 0x02a00093
            soc.uncore.ram_i.mem[0] = 32'h02a0_0093;
            // Instruction 1: lui x2, 0x80010   -> 0x80010137
            soc.uncore.ram_i.mem[1] = 32'h8001_0137;
            // Instruction 2: sw x1, 0(x2)      -> 0x00112023 (store 0x2a to 0x8001_0000)
            soc.uncore.ram_i.mem[2] = 32'h0011_2023;
            // Instruction 3: loop: beq x0, x0, loop -> 0x00000063
            soc.uncore.ram_i.mem[3] = 32'h0000_0063;

            // Initialize DRAM[0] to 0x00001000 so byte 1 is 0x10 and byte 0 is 0x00
            soc.uncore.ram_d.mem[0] = 32'h0000_1000;
        end
    endtask

    int t1_pass = 0;
    int t2_run_pass = 0;
    int t2_pin_pass = 0;
    int t2_cmd_pass = 0;

    initial begin
        $display("==================================================================");
        $display(" Running HWSTRB & Bus Ownership Verification Regression");
        $display("==================================================================");

        dbg_sel = 1'b0;
        uart_rx = 1'b1;
        reset   = 1'b1;
        load_program();

        // Release reset to let debugger boot
        repeat (5) @(posedge clk);
        reset = 1'b0;

        // Wait for Debugger startup banner
        wait (soc.u_debugger.u_socdebug_ahb.u_adp_control.banner == 1'b0);
        wait_for_prompt();
        $display("[TB] Debugger prompt ready.");

        // =====================================================================
        // TEST 1 (T1): Core Store Interrupted by Halt on Data Cycle
        // =====================================================================
        $display("\n--- Starting Test T1: Core Store Interrupted by Halt on Data Cycle ---");
        // Reset core only to restart from PC=0x8000_0000
        force soc.dbg_core_reset = 1'b1;
        load_program();
        repeat (4) @(posedge clk);
        force soc.dbg_core_reset = 1'b0;

        // Wait for core to initiate the store address phase:
        while (!(soc.core_HTRANS == 2'b10 && soc.core_HWRITE == 1'b1 && soc.core_HADDR == 32'h8001_0000)) begin
            @(posedge clk);
        end
        $display("[T1] Detected core store address phase: Addr=0x%08x", soc.core_HADDR);

        // Assert external halt pin on the store address phase so it takes effect on the data cycle
        force soc.u_step_controller.core_stall_ext_i = 1'b1;

        // Transition to data phase cycle:
        @(posedge clk);
        #1; // Allow combinational logic to settle
        $display("[T1] Data cycle: dbg_core_halt_status=%b, HWSTRB=%b, core_HWSTRB=%b, dbg_HWSTRB=%b, HSIZE=%b, HADDR=0x%08x",
                 soc.dbg_core_halt_status, soc.HWSTRB, soc.core_HWSTRB, soc.dbg_HWSTRB, soc.HSIZE, soc.HADDR);

        // Complete data cycle on HREADY
        while (!soc.HREADY) begin
            @(posedge clk);
        end
        @(posedge clk);
        // Release external stall pin so core resumes execution towards loop
        release soc.u_step_controller.core_stall_ext_i;

        $display("[T1] After store completion, DRAM[0] = 0x%08x", soc.uncore.ram_d.mem[0]);
        if (soc.uncore.ram_d.mem[0] === 32'h0000_002a) begin
            $display("[T1 PASS] sw 0x2a successfully wrote full word 0x0000002a!");
            t1_pass = 1;
        end else begin
            $display("[T1 FAIL] sw 0x2a left 0x%08x instead of 0x0000002a! (Strobe truncated to lane 0)",
                     soc.uncore.ram_d.mem[0]);
            t1_pass = 0;
        end

        // Wait for core to reach loop
        repeat (10) @(posedge clk);

        // =====================================================================
        // TEST 2A (T2 running): Debugger Write while Core is Running
        // =====================================================================
        $display("\n--- Starting Test T2 (running): Debugger Write with Core Running ---");
        $display("[T2 running] Core halt status = %b (expect 0 = running)", soc.dbg_core_halt_status);
        soc.uncore.ram_d.mem[4] = 32'h0000_0000;

        // Debugger sets address pointer to 0x8001_0010 (DRAM[4]) and writes 0xAABBCCDD
        send_uart_string("A 80010010\n");
        wait_for_prompt();
        send_uart_string("W AABBCCDD\n");
        wait_for_prompt();

        $display("[T2 running] Written DRAM[4] = 0x%08x", soc.uncore.ram_d.mem[4]);
        if (soc.uncore.ram_d.mem[4] === 32'hAABB_CCDD) begin
            $display("[T2 running PASS] Debugger successfully wrote 0xAABBCCDD while core running!");
            t2_run_pass = 1;
        end else begin
            $display("[T2 running FAIL] Debugger word write became 0x%08x instead of 0xAABBCCDD!",
                     soc.uncore.ram_d.mem[4]);
            t2_run_pass = 0;
        end

        // =====================================================================
        // TEST 2B (T2 halted by pin): Debugger Write with Core Halted by Pin
        // =====================================================================
        $display("\n--- Starting Test T2 (halted by pin): Debugger Write with Core Halted by Pin ---");
        force soc.u_step_controller.core_stall_ext_i = 1'b1;
        repeat (5) @(posedge clk);
        $display("[T2 pin] Core halt status = %b (expect 1 = halted)", soc.dbg_core_halt_status);
        soc.uncore.ram_d.mem[5] = 32'h0000_0000;

        send_uart_string("A 80010014\n");
        wait_for_prompt();
        send_uart_string("W 11223344\n");
        wait_for_prompt();

        $display("[T2 pin] Written DRAM[5] = 0x%08x", soc.uncore.ram_d.mem[5]);
        if (soc.uncore.ram_d.mem[5] === 32'h1122_3344) begin
            $display("[T2 halted by pin PASS] Debugger successfully wrote 0x11223344 while core halted by pin!");
            t2_pin_pass = 1;
        end else begin
            $display("[T2 halted by pin FAIL] Debugger word write became 0x%08x instead of 0x11223344!",
                     soc.uncore.ram_d.mem[5]);
            t2_pin_pass = 0;
        end
        release soc.u_step_controller.core_stall_ext_i;
        repeat (5) @(posedge clk);

        // =====================================================================
        // TEST 2C (T2 halted by C cmd): Debugger Write with Core Halted by 'C 0202'
        // =====================================================================
        $display("\n--- Starting Test T2 (halted by C cmd): Debugger Write with Core Halted by 'C 0202' ---");
        send_uart_string("C 0202\n"); // Halt core via debugger GPO8[1]
        wait_for_prompt();
        $display("[T2 C cmd] Core halt status = %b (expect 1 = halted)", soc.dbg_core_halt_status);
        soc.uncore.ram_d.mem[6] = 32'h0000_0000;

        send_uart_string("A 80010018\n");
        wait_for_prompt();
        send_uart_string("W 55667788\n");
        wait_for_prompt();

        $display("[T2 C cmd] Written DRAM[6] = 0x%08x", soc.uncore.ram_d.mem[6]);
        if (soc.uncore.ram_d.mem[6] === 32'h5566_7788) begin
            $display("[T2 halted by C cmd PASS] Debugger successfully wrote 0x55667788 while core halted by C command!");
            t2_cmd_pass = 1;
        end else begin
            $display("[T2 halted by C cmd FAIL] Debugger word write became 0x%08x instead of 0x55667788!",
                     soc.uncore.ram_d.mem[6]);
            t2_cmd_pass = 0;
        end

        // Resume core
        send_uart_string("C 0102\n");
        wait_for_prompt();

        // =====================================================================
        // REGRESSION SUMMARY
        // =====================================================================
        $display("\n==================================================================");
        $display("                   REGRESSION TEST RESULTS                        ");
        $display("==================================================================");
        $display(" T1 (Core Store Interrupted by Halt) : %s", t1_pass     ? "PASS" : "FAIL");
        $display(" T2 (Debugger Write - Core Running)   : %s", t2_run_pass ? "PASS" : "FAIL");
        $display(" T2 (Debugger Write - Halted by Pin)  : %s", t2_pin_pass ? "PASS" : "FAIL");
        $display(" T2 (Debugger Write - Halted by C cmd): %s", t2_cmd_pass ? "PASS" : "FAIL");
        $display("==================================================================");

        $finish;
    end

endmodule
