`default_nettype none
module async_fifo #(
    parameter int WIDTH = 8,
    parameter int DEPTH = 4
)(
    input logic wr_clk,
    input logic wr_rstn,
    input logic wr_en,
    input logic [WIDTH-1:0] wr_data,
    output logic wr_full,

    input logic rd_clk,
    input logic rd_rstn,
    input logic rd_en,
    output logic [WIDTH-1:0] rd_data,
    output logic rd_empty
);
localparam int AW = $clog2(DEPTH);

logic [WIDTH-1:0] mem [DEPTH];
logic [AW:0] wr_bin_q, rd_bin_q;
logic [AW:0] wr_gray_q, rd_gray_q;
logic [AW:0] wr_gray_rd_q1, wr_gray_rd_q2;
logic [AW:0] rd_gray_wr_q1, rd_gray_wr_q2;
logic [AW:0] wr_bin_next, rd_bin_next;
logic [AW:0] wr_gray_next, rd_gray_next;
logic wr_fire, rd_fire;

function automatic logic [AW:0] bin2gray(input logic [AW:0] b);
    return (b >> 1) ^ b;
endfunction

assign wr_full = (bin2gray(wr_bin_q + (AW+1)'(1)) == {~rd_gray_wr_q2[AW:AW-1], rd_gray_wr_q2[AW-2:0]});
assign rd_empty = (rd_gray_q == wr_gray_rd_q2);

assign wr_fire = wr_en & ~wr_full;
assign rd_fire = rd_en & ~rd_empty;

assign wr_bin_next = wr_bin_q + (AW+1)'(wr_fire);
assign rd_bin_next = rd_bin_q + (AW+1)'(rd_fire);
assign wr_gray_next = bin2gray(wr_bin_next);
assign rd_gray_next = bin2gray(rd_bin_next);

always_ff @(posedge wr_clk) begin
    if (!wr_rstn) begin
        wr_bin_q  <= '0;
        wr_gray_q <= '0;
    end else begin
        wr_bin_q  <= wr_bin_next;
        wr_gray_q <= wr_gray_next;
    end
end

// per entry icg for fanout
genvar gi;
generate
    for (gi = 0; gi < DEPTH; gi++) begin : g_mem
        logic wr_sel;
        logic mem_clk;
        assign wr_sel = wr_fire & (wr_bin_q[AW-1:0] == AW'(gi));
        OPENROAD_CLKGATE u_cg_mem (.CK(wr_clk), .E(wr_sel), .GCK(mem_clk));
        always_ff @(posedge mem_clk) begin
            mem[gi] <= wr_data;
        end
    end
endgenerate

always_ff @(posedge wr_clk) begin
    if (!wr_rstn) begin
        rd_gray_wr_q1 <= '0;
        rd_gray_wr_q2 <= '0;
    end else begin
        rd_gray_wr_q1 <= rd_gray_q;
        rd_gray_wr_q2 <= rd_gray_wr_q1;
    end
end

always_ff @(posedge rd_clk) begin
    if (!rd_rstn) begin
        rd_bin_q  <= '0;
        rd_gray_q <= '0;
    end else begin
        rd_bin_q  <= rd_bin_next;
        rd_gray_q <= rd_gray_next;
    end
end

always_ff @(posedge rd_clk) begin
    if (!rd_rstn) begin
        wr_gray_rd_q1 <= '0;
        wr_gray_rd_q2 <= '0;
    end else begin
        wr_gray_rd_q1 <= wr_gray_q;
        wr_gray_rd_q2 <= wr_gray_rd_q1;
    end
end

assign rd_data = mem[rd_bin_q[AW-1:0]];

endmodule
`default_nettype wire
