// post processing (pipleined the shft into two stages)
`default_nettype none
module postproc #(
    parameter int N = sys_pkg::p_n,
    parameter int DW = sys_pkg::p_dw,
    parameter int ACC_W = sys_pkg::p_acc_w,
    parameter int SH_W = sys_pkg::p_shift_w
) (
    input logic i_clk,
    input logic i_rstn,
    input logic i_post_proc_en,
    input logic [ACC_W-1:0] i_round_const,
    input logic i_relu_en,
    input logic [SH_W-1:0] i_shift,
    input logic i_arr_valid,
    input logic [N*ACC_W-1:0] i_sys_data,
    output logic o_post_proc_ready,
    output logic o_round_valid,
    output logic [N*ACC_W-1:0] o_round_data,
    output logic o_relu_valid,
    output logic [N*DW-1:0] o_relu_data,
    output logic [N*DW-1:0] o_post_proc_data
);
localparam int SH_LO = 2;

logic pp_fire;
logic mid_valid_q, round_valid_q, relu_valid_q;
logic mid_clk, round_clk, relu_clk;
logic [SH_W-1:0] shift_q;
logic [N*ACC_W-1:0] mid_comb, mid_q, round_comb, round_q;
logic [N*DW-1:0] relu_comb, relu_q;

assign pp_fire = i_post_proc_en & i_arr_valid;

genvar lane;
generate
    for (lane = 0; lane < N; lane++) begin : g_round
        logic signed [ACC_W:0] x_ext, bias_ext, sum_ext;
        logic [ACC_W:0] bias_bits;
        logic [SH_W-1:0] sh_lo, sh_hi;

        always_comb begin
            x_ext = $signed({i_sys_data[lane*ACC_W + ACC_W-1], i_sys_data[lane*ACC_W +: ACC_W]});
            bias_bits = (i_shift == '0) ? '0 : {1'b0, i_round_const};
            bias_ext = $signed(bias_bits);
            sum_ext = x_ext + bias_ext;
            sh_lo = SH_W'(i_shift[SH_LO-1:0]);
            mid_comb[lane*ACC_W +: ACC_W] = ACC_W'(sum_ext >>> sh_lo);
        end

        always_comb begin
            sh_hi = {shift_q[SH_W-1:SH_LO], {SH_LO{1'b0}}};
            round_comb[lane*ACC_W +: ACC_W] = ACC_W'($signed(mid_q[lane*ACC_W +: ACC_W]) >>> sh_hi);
        end
    end
endgenerate

relu #(.N(N), .DW(DW), .ACC_W(ACC_W)) u_relu (
    .i_data(round_q), .i_relu_en(i_relu_en), .o_data(relu_comb)
);

OPENROAD_CLKGATE u_cg_mid   (.CK(i_clk), .E(pp_fire),       .GCK(mid_clk));
OPENROAD_CLKGATE u_cg_round (.CK(i_clk), .E(mid_valid_q),   .GCK(round_clk));
OPENROAD_CLKGATE u_cg_relu  (.CK(i_clk), .E(round_valid_q), .GCK(relu_clk));

always_ff @(posedge mid_clk) begin
    mid_q   <= mid_comb;
    shift_q <= i_shift;
end

always_ff @(posedge round_clk) begin
    round_q <= round_comb;
end

always_ff @(posedge relu_clk) begin
    relu_q <= relu_comb;
end

always_ff @(posedge i_clk) begin
    if (!i_rstn) begin
        mid_valid_q   <= 1'b0;
        round_valid_q <= 1'b0;
        relu_valid_q  <= 1'b0;
    end else begin
        mid_valid_q   <= pp_fire;
        round_valid_q <= mid_valid_q;
        relu_valid_q  <= round_valid_q;
    end
end

assign o_post_proc_ready = i_post_proc_en;
assign o_round_valid = round_valid_q;
assign o_round_data = round_q;
assign o_relu_valid = relu_valid_q;
assign o_relu_data = relu_q;
assign o_post_proc_data = relu_q;

endmodule
`default_nettype wire
