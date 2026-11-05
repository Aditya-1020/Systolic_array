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
logic [N*ACC_W-1:0] round_comb;
logic [N*ACC_W-1:0] round_q;
logic [N*DW-1:0] relu_comb;
logic [N*DW-1:0] relu_q;
logic stage1_valid_q;
logic stage2_valid_q;
logic pp_fire, cg_en, pp_clk;

assign pp_fire = i_post_proc_en & i_arr_valid;

assign cg_en = pp_fire | stage1_valid_q | stage2_valid_q;
OPENROAD_CLKGATE u_cg_postproc (.CK(i_clk),.E(cg_en), .GCK(pp_clk));

round #(.N(N), .ACC_W(ACC_W), .SH_W(SH_W)) u_round (
    .i_data(i_sys_data), .i_shift(i_shift), 
    .i_round_const(i_round_const), .o_data(round_comb)
);

relu #(.N(N), .DW(DW), .ACC_W(ACC_W)) u_relu (.i_data(round_q), .i_relu_en(i_relu_en), .o_data(relu_comb));

always_ff @(posedge pp_clk or negedge i_rstn) begin
    if (!i_rstn) begin
        round_q <= '0;
        relu_q <= '0;
        stage1_valid_q <= 1'b0;
        stage2_valid_q <= 1'b0;
    end else begin
        if (pp_fire)
            round_q <= round_comb;
        if (stage1_valid_q)
            relu_q <= relu_comb;

        stage1_valid_q <= pp_fire;
        stage2_valid_q <= stage1_valid_q;
    end
end

assign o_post_proc_ready = i_post_proc_en;
assign o_round_valid = stage1_valid_q;
assign o_round_data = round_q;
assign o_relu_valid = stage2_valid_q;
assign o_relu_data = relu_q;
assign o_post_proc_data  = relu_q;

endmodule
`default_nettype wire
