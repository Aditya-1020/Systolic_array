// 3 stage (mul not in same as capture)
`default_nettype none
module pe #(
    parameter int DW = sys_pkg::p_dw,
    parameter int ACC_W = sys_pkg::p_acc_w
) (
    input logic i_clk_w,
    input logic i_clk_adv,
    input logic signed [DW-1:0] i_w,
    input logic signed [DW-1:0] i_a,
    input logic signed [ACC_W-1:0] i_psum,
    output logic signed [DW-1:0] o_w,
    output logic signed [DW-1:0] o_a,
    output logic signed [ACC_W-1:0] o_psum
);

logic signed [DW-1:0] a_s1, a_s2;
logic signed [ACC_W-1:0] psum_s1, psum_s2;
logic signed [ACC_W-1:0] prod_s2;

always_ff @(posedge i_clk_w) begin
    o_w <= i_w;
end

always_ff @(posedge i_clk_adv) begin
    a_s1 <= i_a;
    psum_s1 <= i_psum;
    a_s2 <= a_s1;
    psum_s2 <= psum_s1;
    prod_s2 <= ACC_W'(a_s1 * o_w);
    o_a <= a_s2;
    o_psum <= psum_s2 + prod_s2;
end

endmodule
`default_nettype wire
