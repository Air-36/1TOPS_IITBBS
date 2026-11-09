// =============================================================================
// Module: tb_soc_full_top
// Purpose: Top-level Testbench for Full 1TOPS RISC-V SoC Verification
//          Integrates:
//          - Full SoC with Pipelined RISC-V Core & Uncore Subsystem
//          - Instruction Memory & Data Memory Preloading (.hex/.mem)
//          - GPIO UVM VIP (Bidirectional Stimulus & Checking)
//          - IRQ UVM VIP (CLINT Timer/SW & PLIC External Interrupts)
//          - UART UVM VIP & Console Stream Monitor
//          - SPI Flash Behavioral Model (Read 0x03 & Bootloader Image)
//          - CPU Execution & Mailbox Signature Monitor
//          - AHB & APB SystemVerilog Assertions (SVA)
// =============================================================================

`timescale 1ns/1ps

import uvm_pkg::*;
`include "uvm_macros.svh"

import gpio_pkg::*;
import irq_pkg::*;
import uart_pkg::*;
import soc_full_env_pkg::*;

module tb_soc_full_top #(
    parameter bit        USE_BOOTROM = 0,
    parameter bit [31:0] RESET_PC    = USE_BOOTROM ? 32'h0000_1000 : 32'h8000_0000
);

    // -------------------------------------------------------------------------
    // Clock and Reset Generation
    // -------------------------------------------------------------------------
    logic clk;
    logic reset;
    logic boot_mode_pin;

    // 100 MHz System Clock (10 ns period)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Power-On Reset Sequence
    initial begin
        reset = 1;
        #100;
        @(posedge clk);
        reset = 0;
    end

    // Boot mode strap selection
    initial begin
        boot_mode_pin = 1'b0;
        if ($test$plusargs("BOOT_MODE_1")) begin
            boot_mode_pin = 1'b1;
            $display("[TB_TOP] Configured Boot Mode 1: SPI Flash Boot");
        end else begin
            $display("[TB_TOP] Configured Boot Mode 0: Internal ROM Boot");
        end
    end

    // -------------------------------------------------------------------------
    // VIP Interfaces
    // -------------------------------------------------------------------------
    gpio_if gpio_vif (.clk(clk), .rst_n(~reset));
    irq_if  irq_vif  (.clk(clk), .rst_n(~reset));
    uart_if uart_vif (.clk(clk), .rst_n(~reset));

    // -------------------------------------------------------------------------
    // SoC Peripheral Wires
    // -------------------------------------------------------------------------
    wire [31:0] GPIOOUT, GPIOEN;
    wire [31:0] GPIOIN = gpio_vif.gpio_in;
    assign gpio_vif.gpio_out = GPIOOUT;
    assign gpio_vif.gpio_oe  = GPIOEN;

    wire UARTSout;
    wire UARTSin = uart_vif.sin;
    assign uart_vif.sout = UARTSout;

    wire        SPICLK;
    wire [3:0]  SPICS;
    wire        SPIOut;
    wire        SPIIn;

    wire [31:0] PCW, ResultW;
    wire        TrapM, mretM;

    // -------------------------------------------------------------------------
    // DUT: riscv_soc_ahb
    // -------------------------------------------------------------------------
    riscv_soc_ahb #(
        .RESET_PC(RESET_PC),
        .MEM_SIZE_BYTES(65536)
    ) u_dut (
        .clk(clk),
        .reset(reset),
        .boot_mode(boot_mode_pin),

        // Interrupts
        .MExtInt(1'b0), // top pin external interrupt
        .TrapM(TrapM),
        .mretM(mretM),

        // Execution hooks
        .PCW(PCW),
        .ResultW(ResultW),

        // Peripherals
        .GPIOIN(GPIOIN),
        .GPIOOUT(GPIOOUT),
        .GPIOEN(GPIOEN),
        .UARTSin(UARTSin),
        .UARTSout(UARTSout),
        .SPIIn(SPIIn),
        .SPIOut(SPIOut),
        .SPICS(SPICS),
        .SPICLK(SPICLK),

        // Debugger (idle in default testbench)
        .dbg_sel(1'b0),
        .uart_rx(1'b1),
        .uart_tx(),
        .ft1248_clk(),
        .ft1248_ss_n(),
        .ft1248_miso(1'b1),
        .ft1248_miosio(),
        .core_halted_led()
    );

    // -------------------------------------------------------------------------
    // Connect IRQ VIP Interface to Uncore Interrupt Lines
    // -------------------------------------------------------------------------
    // Bit 0: MTimerInt (CLINT)
    // Bit 1: MSwInt (CLINT)
    // Bit 2: MExtInt (PLIC Core line)
    // Bit 3: GPIOIntr (GPIO peripheral line)
    // Bit 4: UARTIntr (UART peripheral line)
    // Bit 5: SPIIntr (SPI peripheral line)
    assign irq_vif.irq_lines[0] = u_dut.MTimerInt;
    assign irq_vif.irq_lines[1] = u_dut.MSwInt;
    assign irq_vif.irq_lines[2] = u_dut.core_MExtInt;
    assign irq_vif.irq_lines[3] = u_dut.uncore.GPIOIntr;
    assign irq_vif.irq_lines[4] = u_dut.uncore.UARTIntr;
    assign irq_vif.irq_lines[5] = u_dut.uncore.SPIIntr;
    assign irq_vif.irq_lines[15:6] = '0;

    // -------------------------------------------------------------------------
    // SPI Flash Behavioral Model
    // -------------------------------------------------------------------------
    spi_flash_model u_spi_flash (
        .sclk(SPICLK),
        .cs_n(SPICS[0]),
        .mosi(SPIOut),
        .miso(SPIIn)
    );

    // -------------------------------------------------------------------------
    // CPU Execution & Verification Mailbox Monitor
    // -------------------------------------------------------------------------
    wire test_passed, test_failed, plic_armed;
    wire [31:0] error_code;

    cpu_exec_monitor u_cpu_mon (
        .clk(clk),
        .reset(reset),
        .PCW(PCW),
        .ResultW(ResultW),
        .TrapM(TrapM),
        .mretM(mretM),
        .HADDR(u_dut.HADDR),
        .HWDATA(u_dut.HWDATA),
        .HWRITE(u_dut.HWRITE),
        .HTRANS(u_dut.HTRANS),
        .HREADY(u_dut.HREADY),
        .test_passed(test_passed),
        .test_failed(test_failed),
        .plic_armed(plic_armed),
        .error_code(error_code)
    );

    // -------------------------------------------------------------------------
    // Memory Preloading (.mem files into IRAM & DRAM)
    // -------------------------------------------------------------------------
    string instr_mem_file = "fw_boot_bringup_instr.mem";
    string data_mem_file  = "fw_boot_bringup_data.mem";

    initial begin
        void'($value$plusargs("INSTR_MEM=%s", instr_mem_file));
        void'($value$plusargs("DATA_MEM=%s", data_mem_file));

        #1;
        if (!USE_BOOTROM) begin
            $readmemh(instr_mem_file, u_dut.uncore.ram_i.mem);
            $readmemh(data_mem_file,  u_dut.uncore.ram_d.mem);
            $display("[TB_TOP] Successfully preloaded IRAM from %s", instr_mem_file);
            $display("[TB_TOP] Successfully preloaded DRAM from %s", data_mem_file);
        end else begin
            $display("[TB_TOP] Running Boot ROM test: PC boots at 0x0000_1000");
        end
    end

    // -------------------------------------------------------------------------
    // UART Character Sniffer -> UVM analysis port
    // -------------------------------------------------------------------------
    uvm_root root_h;
    soc_full_env env_h;

    always @(posedge clk) begin
        if (!reset && u_dut.uncore.gen_uart.uart.memwrite) begin
            if (u_dut.uncore.gen_uart.uart.PADDR == 3'b000 && !u_dut.uncore.gen_uart.uart.lcr[7]) begin
                // Character sent
                root_h = uvm_root::get();
                if ($cast(env_h, root_h.find("uvm_test_top.env"))) begin
                    env_h.uart_agt.monitor.record_char(u_dut.uncore.gen_uart.uart.din);
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // Protocol Checkers (SVA)
    // -------------------------------------------------------------------------
    ahb_protocol_checker u_ahb_chk (
        .HCLK(clk),
        .HRESETn(~reset),
        .HADDR(u_dut.HADDR),
        .HTRANS(u_dut.HTRANS),
        .HWRITE(u_dut.HWRITE),
        .HSIZE(3'b010),
        .HREADY(u_dut.HREADY),
        .HRESP(u_dut.HRESP),
        .HWDATA(u_dut.HWDATA)
    );

    apb_protocol_checker u_apb_chk (
        .PCLK(clk),
        .PRESETn(~reset),
        .PSEL(u_dut.uncore.PSEL),
        .PENABLE(u_dut.uncore.PENABLE),
        .PWRITE(u_dut.uncore.PWRITE),
        .PADDR(u_dut.uncore.PADDR),
        .PREADY(u_dut.uncore.PREADY),
        .PSLVERR(1'b0)
    );

    // -------------------------------------------------------------------------
    // UVM Configuration & Start
    // -------------------------------------------------------------------------
    initial begin
        // Set virtual interfaces
        uvm_config_db#(virtual gpio_if)::set(null, "*", "gpio_vif", gpio_vif);
        uvm_config_db#(virtual irq_if)::set(null, "*", "irq_vif", irq_vif);
        uvm_config_db#(virtual uart_if)::set(null, "*", "uart_vif", uart_vif);

        // Run selected UVM test
        run_test();
    end

endmodule

