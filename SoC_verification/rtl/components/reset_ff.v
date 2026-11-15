module reset_ff #(parameter WIDTH = 32, RESET_VAL = 0) (
        input       clk, rst, clr,
        input       [WIDTH-1:0] d,
        output reg  [WIDTH-1:0] q
    );

// // synthesis translate_off
// initial begin
//     q = RESET_VAL;
// end
// // synthesis translate_on

    // spyglass disable_block Reset_check07
    // SMD: Clear pin of sequential element is driven by combinational logic
    // SJ: CPU core reset combines chip pad reset, debugger reset, and sysctrl soft reset
    always @(posedge clk or posedge rst) begin
        if (rst) q <= RESET_VAL;
        else if (!clr) q <= d;
    end
    // spyglass enable_block Reset_check07

endmodule
