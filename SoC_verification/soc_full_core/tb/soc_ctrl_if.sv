// =============================================================================
// Interface: soc_ctrl_if
// Purpose: Control & status interface connecting TB top signals to UVM tests
// =============================================================================

`timescale 1ns/1ps

interface soc_ctrl_if (
    input logic clk,
    input logic reset
);
    logic        test_passed;
    logic        test_failed;
    logic        plic_armed;
    logic [31:0] error_code;
    logic        boot_mode_pin;

endinterface : soc_ctrl_if

