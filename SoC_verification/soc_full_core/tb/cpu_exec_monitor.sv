// =============================================================================
// Module: cpu_exec_monitor
// Purpose: CPU Execution & Verification Mailbox Monitor
// =============================================================================

`timescale 1ns/1ps

module cpu_exec_monitor (
    input  logic        clk,
    input  logic        reset,

    // CPU Pipeline execution signals
    input  logic [31:0] PCW,
    input  logic [31:0] ResultW,
    input  logic        TrapM,
    input  logic        mretM,

    // SoC AHB bus signals
    input  logic [31:0] HADDR,
    input  logic [31:0] HWDATA,
    input  logic        HWRITE,
    input  logic [ 1:0] HTRANS,
    input  logic        HREADY,

    // Status outputs to testbench
    output logic        test_passed,
    output logic        test_failed,
    output logic        plic_armed,
    output logic [31:0] error_code
);

    logic [31:0] prev_haddr;
    logic        prev_write;

    // Track address phase of AHB writes
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            prev_haddr  <= 32'd0;
            prev_write  <= 1'b0;
            test_passed <= 1'b0;
            test_failed <= 1'b0;
            plic_armed  <= 1'b0;
            error_code  <= 32'd0;
        end else if (HREADY) begin
            if (TrapM) begin
                $display("[CPU_MONITOR @ %0t] >>> TRAP DETECTED! PCW=0x%08x <<<", $time, PCW);
            end
            if (HTRANS[1] && HWRITE) begin
                prev_haddr <= HADDR;
                prev_write <= 1'b1;
            end else begin
                prev_write <= 1'b0;
            end

            // Data phase of write
            if (prev_write) begin
                // Check Mailbox Status write (0x8001_7FFC)
                if (prev_haddr == 32'h8001_7FFC) begin
                    if (HWDATA == 32'hCAFE_BABE || HWDATA == 32'd1) begin
                        test_passed <= 1'b1;
                        $display("[CPU_MONITOR @ %0t] >>> PASS DETECTED! Mailbox = 0x%08x <<<", $time, HWDATA);
                    end else if (HWDATA == 32'h1234_5678) begin
                        plic_armed <= 1'b1;
                        $display("[CPU_MONITOR @ %0t] >>> PLIC ARMED! Mailbox = 0x%08x <<<", $time, HWDATA);
                    end else if (HWDATA == 32'hDEAD_BEEF) begin
                        test_failed <= 1'b1;
                        $display("[CPU_MONITOR @ %0t] >>> FAIL DETECTED! Mailbox = 0x%08x <<<", $time, HWDATA);
                    end
                end

                // Check SYSCTRL Scratchpad write (0x1008_0014) - Used by Boot ROM for PASS signature
                if (prev_haddr == 32'h1008_0014) begin
                    if (HWDATA == 32'd1 || HWDATA == 32'd42) begin
                        test_passed <= 1'b1;
                        $display("[CPU_MONITOR @ %0t] >>> PASS DETECTED! Scratchpad = 0x%08x <<<", $time, HWDATA);
                    end
                end

                // Check TOHOST write (0x8000_1000)
                if (prev_haddr == 32'h8000_1000) begin
                    if (HWDATA == 32'd1) begin
                        test_passed <= 1'b1;
                        $display("[CPU_MONITOR @ %0t] >>> PASS DETECTED! TOHOST = 1 <<<", $time);
                    end else if (HWDATA != 0) begin
                        test_failed <= 1'b1;
                        error_code <= HWDATA >> 1;
                        $display("[CPU_MONITOR @ %0t] >>> FAIL DETECTED! TOHOST = 0x%08x <<<", $time, error_code);
                    end
                end
            end
        end
    end

endmodule

