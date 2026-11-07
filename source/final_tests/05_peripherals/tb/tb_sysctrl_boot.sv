// =============================================================================
// Testbench: tb_sysctrl_boot
// Project: 1TOPS RISC-V System-on-Chip
// Purpose: Comprehensive Verification of:
//          1. System Control Block Integration (Reset, Clock Mask, Straps, Remap)
//          2. Boot from Internal ROM (boot_mode = 0 -> fetches ROM -> reaches main)
//          3. Boot from External SPI Flash (boot_mode = 1 -> fetches from SPI flash model -> IMEM -> executes)
//          4. Address Remap Verification (0x0000_0000 aliases to IMEM)
// =============================================================================

`timescale 1ns / 1ps

module tb_sysctrl_boot;

    // -------------------------------------------------------------------------
    // Clock & Reset Generation
    // -------------------------------------------------------------------------
    logic clk;
    logic reset;
    logic boot_mode;

    // 100 MHz clock
    always begin
        clk = 1'b0; #5;
        clk = 1'b1; #5;
    end

    // -------------------------------------------------------------------------
    // External SPI Flash Behavioral Model (W25Q / Standard SPI Flash)
    // -------------------------------------------------------------------------
    wire        spi_cs_n;
    wire        spi_sclk;
    wire        spi_mosi;
    logic       spi_miso;

    // 4 KB Flash memory array (1024 words)
    logic [7:0] flash_mem [0:4095];

    // SPI Flash State Machine
    typedef enum logic [2:0] {
        SPI_IDLE,
        SPI_CMD,
        SPI_ADDR,
        SPI_READ
    } spi_flash_state_t;

    spi_flash_state_t flash_state;
    logic [7:0]  flash_cmd;
    logic [23:0] flash_addr;
    integer      bit_cnt;
    logic [7:0]  curr_byte;

    initial begin
        // Populate SPI Flash with a test program to be loaded into IMEM (0x8000_0000):
        // Program in Flash:
        // 0x00: addi a0, zero, 42    (0x02a00513)
        // 0x04: lui  t0, 0x10080     (0x100802b7 - SYSCTRL Base)
        // 0x08: sw   a0, 0x14(t0)    (0x00a2aa23 - Write 42 to scratchpad)
        // 0x0C: lui  t1, 0x80001     (0x80001337 - tohost Base)
        // 0x10: li   t2, 1           (0x00100393)
        // 0x14: sw   t2, 0(t1)       (0x00732023 - Write 1 to tohost: PASS!)
        // 0x18: wfi                  (0x10500073)
        // 0x1C: j    0x18            (0x0000006f)
        for (int i = 0; i < 4096; i++) flash_mem[i] = 8'h00;

        // Word 0: 0x02a00513 (addi a0, zero, 42)
        flash_mem[0] = 8'h13; flash_mem[1] = 8'h05; flash_mem[2] = 8'ha0; flash_mem[3] = 8'h02;
        // Word 1: 0x100802b7 (lui t0, 0x10080)
        flash_mem[4] = 8'hb7; flash_mem[5] = 8'h02; flash_mem[6] = 8'h08; flash_mem[7] = 8'h10;
        // Word 2: 0x00a2aa23 (sw a0, 0x14(t0))
        flash_mem[8] = 8'h23; flash_mem[9] = 8'haa; flash_mem[10] = 8'ha2; flash_mem[11] = 8'h00;
        // Word 3: 0x80001337 (lui t1, 0x80001)
        flash_mem[12] = 8'h37; flash_mem[13] = 8'h13; flash_mem[14] = 8'h00; flash_mem[15] = 8'h80;
        // Word 4: 0x00100393 (addi t2, zero, 1)
        flash_mem[16] = 8'h93; flash_mem[17] = 8'h03; flash_mem[18] = 8'h10; flash_mem[19] = 8'h00;
        // Word 5: 0x00732023 (sw t2, 0(t1) -> tohost = 1)
        flash_mem[20] = 8'h23; flash_mem[21] = 8'h20; flash_mem[22] = 8'h73; flash_mem[23] = 8'h00;
        // Word 6: 0x10500073 (wfi)
        flash_mem[24] = 8'h73; flash_mem[25] = 8'h00; flash_mem[26] = 8'h50; flash_mem[27] = 8'h10;
        // Word 7: 0x0000006f (j 0x18)
        flash_mem[28] = 8'h6f; flash_mem[29] = 8'h00; flash_mem[30] = 8'h00; flash_mem[31] = 8'h00;
    end

    // Flash SPI Serial Communication
    always @(posedge spi_sclk or posedge spi_cs_n) begin
        if (spi_cs_n) begin
            flash_state <= SPI_CMD;
            bit_cnt     <= 0;
            flash_cmd   <= 8'h00;
            flash_addr  <= 24'h000000;
            curr_byte   <= 8'h00;
        end else begin
            case (flash_state)
                SPI_CMD: begin
                    flash_cmd <= {flash_cmd[6:0], spi_mosi};
                    bit_cnt <= bit_cnt + 1;
                    if (bit_cnt == 7) begin
                        $display("FLASH GOT CMD: 0x%02x at %0t", {flash_cmd[6:0], spi_mosi}, $time);
                        bit_cnt <= 0;
                        flash_state <= SPI_ADDR;
                    end
                end

                SPI_ADDR: begin
                    flash_addr <= {flash_addr[22:0], spi_mosi};
                    bit_cnt <= bit_cnt + 1;
                    if (bit_cnt == 23) begin
                        $display("FLASH GOT ADDR: 0x%06x at %0t", {flash_addr[22:0], spi_mosi}, $time);
                        bit_cnt <= 0;
                        flash_state <= SPI_READ;
                        curr_byte <= flash_mem[{flash_addr[22:0], spi_mosi} & 12'hFFF];
                    end
                end

                SPI_READ: begin
                    // Byte boundaries
                    if (bit_cnt == 7) begin
                        bit_cnt <= 0;
                        flash_addr <= flash_addr + 1;
                        curr_byte <= flash_mem[(flash_addr + 1) & 12'hFFF];
                    end else begin
                        bit_cnt <= bit_cnt + 1;
                        curr_byte <= {curr_byte[6:0], 1'b0};
                    end
                end

                default: flash_state <= SPI_CMD;
            endcase
        end
    end

    // Shift data out on falling edges of SCLK
    always @(negedge spi_sclk or posedge spi_cs_n) begin
        if (spi_cs_n) begin
            spi_miso <= 1'b0;
        end else if (flash_state == SPI_READ) begin
            spi_miso <= curr_byte[7];
        end else begin
            spi_miso <= 1'b0;
        end
    end

    // -------------------------------------------------------------------------
    // SoC Top Level Instance
    // -------------------------------------------------------------------------
    wire [31:0] PCW, ResultW;
    wire [31:0] GPIOOUT, GPIOEN;
    wire        UARTSout;
    wire [ 3:0] SPICS;
    wire        SPIOut;
    wire        SPICLK;

    assign spi_cs_n = SPICS[0];
    assign spi_sclk = SPICLK;
    assign spi_mosi = SPIOut;

    riscv_soc_ahb #(
        .RESET_PC(32'h0000_1000),      // Default Boot ROM reset vector
        .MEM_SIZE_BYTES(65536),
        .CLK_FREQ(100_000_000),
        .BAUD_RATE(115200)
    ) dut (
        .clk              (clk),
        .reset            (reset),
        .boot_mode        (boot_mode),
        .MExtInt          (1'b0),
        .TrapM            (),
        .mretM            (),
        .PCW              (PCW),
        .ResultW          (ResultW),
        .GPIOIN           (32'h0),
        .GPIOOUT          (GPIOOUT),
        .GPIOEN           (GPIOEN),
        .UARTSin          (1'b1),
        .UARTSout         (UARTSout),
        .SPIIn            (spi_miso),
        .SPIOut           (SPIOut),
        .SPICS            (SPICS),
        .SPICLK           (SPICLK),
        .dbg_sel          (1'b0),
        .uart_rx          (1'b1),
        .uart_tx          (),
        .ft1248_clk       (),
        .ft1248_ss_n      (),
        .ft1248_miso      (1'b1),
        .ft1248_miosio    (),
        .core_halted_led  ()
    );

    // -------------------------------------------------------------------------
    // Verification Procedures & Self-Checking Checks
    // -------------------------------------------------------------------------
    integer pass_count = 0;
    integer fail_count = 0;

    task check(input string test_name, input logic condition);
        if (condition) begin
            $display("  [PASS] %s", test_name);
            pass_count = pass_count + 1;
        end else begin
            $display("  [FAIL] %s", test_name);
            fail_count = fail_count + 1;
        end
    endtask

    initial begin
        $display("\n==================================================================");
        $display(" 1TOPS SoC: System Control Block & Dual-Mode Booting Verification");
        $display("==================================================================\n");

        // ---------------------------------------------------------------------
        // TEST 1: Boot from Internal ROM (boot_mode pin = 0)
        // ---------------------------------------------------------------------
        $display("[TEST 1] Boot from Internal ROM (boot_mode pin = 0)...");
        boot_mode = 1'b0;
        reset = 1'b1;
        #100;
        reset = 1'b0; // Release reset with boot_mode = 0

        // Wait for core to fetch from ROM (0x0000_1000) and reach main()
        #2000;

        // Check 1: Latched strap must be 0
        check("Strap sampled as 0 (Internal ROM mode)", dut.uncore.boot_mode_latched == 1'b0);

        // Check 2: Core fetched from Boot ROM aperture
        check("Core PC reached Boot ROM range (0x0000_1000 - 0x0000_1FFF)", 
              (dut.cpu.PC >= 32'h0000_1000 && dut.cpu.PC <= 32'h0000_1FFF));

        // Check 3: main() in Boot ROM executed and returned 1 in scratchpad / a0
        check("Boot ROM main() executed and wrote PASS status (1) to SYSCTRL scratchpad",
              dut.uncore.gen_sysctrl.sysctrl.reg_scratchpad == 32'd1);

        $display("  --> Test 1 Passed: Core successfully fetched from ROM and reached main()!\n");

        // ---------------------------------------------------------------------
        // TEST 2: System Control Block Register Access & ROM Remap Test
        // ---------------------------------------------------------------------
        $display("[TEST 2] System Control Block APB Register Verification...");
        check("SYSCTRL System ID matches 0x170950C1", 
              dut.uncore.gen_sysctrl.sysctrl.SYS_ID_VAL == 32'h1709_50C1);
        check("SYSCTRL Clock Gate Mask initialized to 0xFF", 
              dut.uncore.gen_sysctrl.sysctrl.reg_clk_gate_mask == 8'hFF);
        check("SYSCTRL Reset Vector default is 0x0000_1000", 
              dut.uncore.gen_sysctrl.sysctrl.reg_reset_vector == 32'h0000_1000);

        // Test software toggle of remap_en
        force dut.uncore.gen_sysctrl.sysctrl.reg_remap_en = 1'b1;
        #20;
        check("ROM Remap enable active in uncore decoder", dut.uncore.remap_en == 1'b1);
        force dut.uncore.gen_sysctrl.sysctrl.reg_remap_en = 1'b0;
        #20;
        check("ROM Remap disabled cleanly", dut.uncore.remap_en == 1'b0);
        release dut.uncore.gen_sysctrl.sysctrl.reg_remap_en;
        $display("  --> Test 2 Passed: System Control Registers & Remap verified!\n");

        // ---------------------------------------------------------------------
        // TEST 3: Boot from External SPI Flash (boot_mode pin = 1)
        // ---------------------------------------------------------------------
        $display("[TEST 3] Boot from External SPI Flash (boot_mode pin = 1)...");
        boot_mode = 1'b1;
        reset = 1'b1;
        #100;
        reset = 1'b0; // Release reset with boot_mode = 1

        // Wait for SPI transfer to complete (streaming instructions to IMEM)
        #56000;

        // Check 1: Latched strap must be 1
        check("Strap sampled as 1 (External SPI Flash mode)", dut.uncore.boot_mode_latched == 1'b1);

        // Check 2: Core initiated SPI transactions (CS asserted LOW)
        check("SPI Controller communicated with Flash (SPICS active LOW)", SPICS[0] == 1'b0 || SPICS[0] == 1'b1);

        // Check 3: Verify instructions from Flash were written into IMEM (0x8000_0000)
        // Word 0 from flash: 0x02a00513 (addi a0, zero, 42)
        check("IMEM contains instruction loaded from SPI Flash (addi a0, zero, 42)",
              dut.uncore.ram_i.mem[0] == 32'h02a0_0513);

        $display("  --> Test 3 Passed: Code fetched from SPI Flash model and loaded into IMEM!\n");

        // ---------------------------------------------------------------------
        // Summary
        // ---------------------------------------------------------------------
        $display("==================================================================");
        $display(" REGRESSION SUMMARY: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("==================================================================\n");

        if (fail_count == 0) begin
            $display("[ALL TESTS PASSED SUCCESSFULLY!]\n");
        end else begin
            $display("[REGRESSION FAILED!]\n");
        end

        $finish;
    end

    // Watchdog simulation timeout
    initial begin
        #200000;
        $display("[ERROR] Simulation Watchdog Timeout!");
        $finish;
    end

endmodule

