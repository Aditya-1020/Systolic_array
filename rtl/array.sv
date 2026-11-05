`default_nettype none
module array #(
    parameter int N = sys_pkg::p_n,
    parameter int DW = sys_pkg::p_dw,
    parameter int ACC_W = sys_pkg::p_acc_w
) (
    input logic [N*DW-1:0] i_w_stream,
    input logic [N*DW-1:0] i_a_left,
    input logic [N*ACC_W-1:0] i_psum_top,
    input logic i_clk_w,
    input logic i_clk_adv,
    output logic [N*ACC_W-1:0] o_c_bottom
);
logic [N-1:0][N:0][DW-1:0] a_wire;
logic [N:0][N-1:0][DW-1:0] w_wire;
logic [N:0][N-1:0][ACC_W-1:0] psum_wire;

genvar row, col;
generate
    for (row = 0; row < N; row++) begin : g_left_edge
        assign a_wire[row][0] = i_a_left[row*DW +: DW];
    end

    for (col = 0; col < N; col++) begin : g_top_edge
        assign w_wire[N][col] = i_w_stream[col*DW +: DW];
        assign psum_wire[0][col] = i_psum_top[col*ACC_W +: ACC_W];
        assign o_c_bottom[col*ACC_W +: ACC_W] = psum_wire[N][col];
    end

    for (row = 0; row < N; row++) begin : g_rows
        for (col = 0; col < N; col++) begin : g_cols
            pe #(.DW(DW), .ACC_W(ACC_W)) u_pe (
                .i_clk_w   (i_clk_w),
                .i_clk_adv (i_clk_adv),
                .i_w       (w_wire[row+1][col]),
                .i_a       (a_wire[row][col]),
                .i_psum    (psum_wire[row][col]),
                .o_w       (w_wire[row][col]),
                .o_a       (a_wire[row][col+1]),
                .o_psum    (psum_wire[row+1][col])
            );
        end
    end
endgenerate

endmodule
`default_nettype wire
