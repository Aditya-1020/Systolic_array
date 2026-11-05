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
logic signed [2*DW-1:0] prod;
logic signed [ACC_W-1:0] prod_ext;

assign prod = i_a * o_w;
assign prod_ext = ACC_W'(prod);

always_ff @(posedge i_clk_w) begin
    o_w <= i_w;
end

always_ff @(posedge i_clk_adv) begin
    o_a <= i_a;
    o_psum <= i_psum + prod_ext;
end

endmodule
`default_nettype wire
