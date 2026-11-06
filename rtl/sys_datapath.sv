`default_nettype none
module sys_datapath #(
    parameter int N = sys_pkg::p_n,
    parameter int DW = sys_pkg::p_dw,
    parameter int ACC_W = sys_pkg::p_acc_w,
    parameter int SH_W = sys_pkg::p_shift_w
)(
    input wire i_clk,
    input wire i_rstn,
    input wire i_w_load,
    input wire [N*DW-1:0] i_w_data,
    input wire i_a_advance,
    input wire i_a_valid,
    input wire [N*DW-1:0] i_a_data,
    input wire i_post_proc_en,
    input wire i_relu_en,
    input wire [SH_W-1:0] i_shift,
    input wire [ACC_W-1:0] i_round_const,
    output logic o_c_valid,
    output logic [N*ACC_W-1:0] o_c_data,
    output logic o_pp_valid,
    output logic [N*DW-1:0] o_pp_data
);
logic arr_fire;
logic pp_clk, pp_cg_en, pp_round_valid;

assign arr_fire = o_c_valid & i_a_advance;
// Clock only while INT8 postproc pipeline is occupied (or accepting).
assign pp_cg_en = i_post_proc_en & (arr_fire | pp_round_valid | o_pp_valid);

systolic_array #(.N(N), .DW(DW), .ACC_W(ACC_W)) u_array (
    .i_clk      (i_clk),
    .i_rstn     (i_rstn),
    .i_w_load   (i_w_load),
    .i_w_data   (i_w_data),
    .i_a_advance(i_a_advance),
    .i_a_valid  (i_a_valid),
    .i_a_data   (i_a_data),
    .o_c_valid  (o_c_valid),
    .o_c_data   (o_c_data)
);

OPENROAD_CLKGATE u_cg_postproc (.CK(i_clk), .E(pp_cg_en), .GCK(pp_clk));

postproc #(.N(N), .DW(DW), .ACC_W(ACC_W), .SH_W(SH_W)) u_postproc (
    .i_clk            (pp_clk),
    .i_rstn           (i_rstn),
    .i_post_proc_en   (i_post_proc_en),
    .i_round_const    (i_round_const),
    .i_relu_en        (i_relu_en),
    .i_shift          (i_shift),
    .i_arr_valid      (arr_fire),
    .i_sys_data       (o_c_data),
    .o_post_proc_ready(),
    .o_round_valid    (pp_round_valid),
    .o_round_data     (),
    .o_relu_valid     (o_pp_valid),
    .o_relu_data      (),
    .o_post_proc_data (o_pp_data)
);

endmodule
`default_nettype wire
