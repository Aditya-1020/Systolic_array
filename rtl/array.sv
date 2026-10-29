`default_nettype none

module array #(
    parameter int N = 8,
    parameter int DW = 8,
    parameter int ACC_W = 24
)(
    input wire i_clk_w,
    input wire i_clk_adv,
    input wire [N*DW-1:0] i_w_stream,
    input wire [N*DW-1:0] i_a_left,
    input wire [N*ACC_W-1:0] i_psum_top,
    output wire signed [N*ACC_W-1:0] o_c_bottom
);
logic signed [N-1:0][N:0][DW-1:0] a_wire;
logic signed [N:0][N-1:0][DW-1:0] w_wire;
logic signed [N:0][N-1:0][ACC_W-1:0] psum_wire;

genvar row, col;
generate
    for (row = 0; row < N; row=row+1) begin : gen_left
        assign a_wire[row][0] = $signed(i_a_left[row*DW +: DW]);
    end
    for (col = 0; col < N; col=col+1) begin : gen_edge
        assign w_wire[N][col] = $signed(i_w_stream[col*DW +: DW]);
        assign psum_wire[0][col] = $signed(i_psum_top[col*ACC_W +: ACC_W]);
        assign o_c_bottom[col*ACC_W +: ACC_W] = psum_wire[N][col];
    end

    for (row = 0; row < N; row = row + 1) begin : gen_pe_row
        for (col = 0; col < N; col = col + 1) begin : gen_pe_col
            pe #(.DW(DW), .ACC_W(ACC_W)) pe_inst (
                .i_clk_w   (i_clk_w),
                .i_clk_adv (i_clk_adv),
                .i_w       ($signed(w_wire[row+1][col])),
                .i_a       ($signed(a_wire[row][col])),
                .i_psum    ($signed(psum_wire[row][col])),
                .o_w       (w_wire[row][col]),
                .o_a       (a_wire[row][col+1]),
                .o_psum    (psum_wire[row+1][col])
            );
        end
    end
endgenerate

endmodule
`default_nettype wire
