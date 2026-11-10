`timescale 1ns/1ps

interface alu_if(input logic clk);

    logic [31:0] a;
    logic [31:0] b;
    logic [3:0]  alu_ctrl;
    logic [31:0] alu_out;
    logic        zero;
    logic        less;
    logic        less_u;

    // Driver clocking block
    clocking drv_cb @(posedge clk);
        default input #1step output #1ns;
        output a, b, alu_ctrl;
    endclocking

    // Monitor clocking block
    clocking mon_cb @(negedge clk);
        default input #1step;
        input a, b, alu_ctrl;
        input alu_out, zero, less, less_u;
    endclocking

endinterface
