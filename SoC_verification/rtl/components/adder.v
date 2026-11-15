module adder #(parameter WIDTH = 32) (
    input       [WIDTH-1:0] a, b,
    output      [WIDTH-1:0] sum
);

wire [WIDTH:0] full_sum = a + b;
assign sum = full_sum[WIDTH-1:0];

endmodule