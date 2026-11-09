module async_fifo_tb_top (
    input  logic       wr_clk,
    input  logic       wr_rstn,
    input  logic       wr_en,
    input  logic [7:0] wr_data,
    output logic       wr_full,
    input  logic       rd_clk,
    input  logic       rd_rstn,
    input  logic       rd_en,
    output logic [7:0] rd_data,
    output logic       rd_empty
);
async_fifo #(
    .WIDTH(8),
    .DEPTH(4),
    .ONEHOT_RD(1'b1)
) u_fifo (
    .wr_clk,
    .wr_rstn,
    .wr_en,
    .wr_data,
    .wr_full,
    .rd_clk,
    .rd_rstn,
    .rd_en,
    .rd_data,
    .rd_empty
);
endmodule
