module spi_fifo #(parameter M=3, N=8)(                 // 2^M entries of N bits each
    input  logic         PCLK, wen, ren, PRESETn,
    input  logic         winc, rinc,
    input  logic [N-1:0] wdata,
    input  logic [M-1:0] wwatermarklevel, rwatermarklevel,
    output logic [N-1:0] rdata,
    output logic         wfull, rempty,
    output logic         wwatermark, rwatermark);

    logic [N-1:0] mem[2**M];
    logic [M:0] rptr, wptr;
    logic [M-1:0] raddr;
    logic [M-1:0] waddr;

    wire write_en = wen & winc & ~wfull;
    wire read_en  = ren & rinc & ~rempty;

    assign rdata = mem[raddr];
    always_ff @(posedge PCLK)
        if (write_en) mem[waddr] <= wdata;

    wire [M:0] wptr_eff = write_en ? (wptr + 1'b1) : wptr;
    wire [M:0] rptr_eff = read_en  ? (rptr + 1'b1) : rptr;

    // write and read pointer and status registers
    always_ff @(posedge PCLK or negedge PRESETn)
        if (~PRESETn) begin
            rptr   <= '0;
            wptr   <= '0;
            wfull  <= 1'b0;
            rempty <= 1'b1;
        end else begin
            if (write_en) wptr <= wptr + 1'b1;
            if (read_en)  rptr <= rptr + 1'b1;
            wfull  <= ({~wptr_eff[M], wptr_eff[M-1:0]} == rptr_eff);
            rempty <= (wptr_eff == rptr_eff);
        end

    assign raddr = rptr[M-1:0];
    assign waddr = wptr[M-1:0];
    assign rwatermark = ((waddr - raddr) < rwatermarklevel) & ~wfull;
    assign wwatermark = ((waddr - raddr) > wwatermarklevel) | wfull;
endmodule
