`default_nettype none
module systolic_core #(
    parameter int N = 8,
    parameter int DW = 8,
    parameter int OUT_W = 32,
    parameter int Q_W = 8,
    parameter int MULT_W = 16,
    parameter int BIAS_W = 16, // int16 bias per lane: |sum| + |bias| < 2^(ACC_W-1), no clamp needed
    parameter int MEM_DW = N*DW,
    parameter int ACC_W = 2*DW + ((N > 1) ? $clog2(N) : 1),
    parameter int SHIFT_W = $clog2(ACC_W + MULT_W + 1)
)(
    input wire i_clk,
    input wire i_rstn,
 
    // static config (CSR flops, write-locked while busy)
    input logic i_relu_en,
    input logic i_quant_en,
    input logic [MULT_W-2:0] i_mult,
    input logic [SHIFT_W-1:0] i_shift,
 
    // WBUF read data, shared by the bias and weight paths
    input logic [MEM_DW-1:0] i_wdata,
    input logic i_bias_shift,
    input logic i_w_shift,
 
    // ABUF read data + sideband
    input logic [N*DW-1:0] i_a_data,
    input logic i_a_vld,
    input logic i_a_last,
    input logic i_flush,
 
    output logic o_c_vld,
    output logic o_c_last,
    output logic [N*OUT_W-1:0] o_c_data
);
 
localparam int LAT = 2*N + 1;
localparam int PP_LAT = 3;
localparam int LAT_PP = LAT + PP_LAT;
 
logic [N*BIAS_W-1:0] bias_q;
logic [N*ACC_W-1:0] bias_acc;
logic clk_w;
 
always_ff @(posedge i_clk) begin
    if (i_bias_shift) begin
        bias_q <= {i_wdata, bias_q[N*BIAS_W-1:MEM_DW]};
    end
end
 
OPENROAD_CLKGATE u_cg_w (.CK(i_clk), .E(i_w_shift), .GCK(clk_w));
 
logic [LAT_PP-1:0] vld_q, last_q;
 
always_ff @(posedge i_clk) begin
    if (!i_rstn || i_flush) begin
        vld_q <= '0;
        last_q <= '0;
    end else begin
        vld_q <= {vld_q[LAT_PP-2:0], i_a_vld};
        last_q <= {last_q[LAT_PP-2:0], (i_a_vld && i_a_last)};
    end
end
 
assign o_c_vld = i_quant_en ? vld_q[LAT_PP-1] : vld_q[LAT-1];
assign o_c_last = i_quant_en ? last_q[LAT_PP-1] : last_q[LAT-1];
 
logic [N*DW-1:0] a_left;
logic [N*ACC_W-1:0] c_bottom;
 
genvar r;
generate
    for (r = 0; r < N; r = r + 1) begin : g_skew
        logic signed [r:0][DW-1:0] sr_q;
        always_ff @(posedge i_clk) begin
            sr_q[0] <= i_a_data[r*DW +: DW];
            for (int k = 1; k <= r; k = k + 1) begin
                sr_q[k] <= sr_q[k-1];
            end
        end
        assign a_left[r*DW +: DW] = sr_q[r];
    end
endgenerate
 
array #(.N(N), .DW(DW), .ACC_W(ACC_W)) u_array (
    .i_clk_w   (clk_w),
    .i_clk_adv (i_clk),
    .i_w_stream(i_wdata[N*DW-1:0]),
    .i_a_left  (a_left),
    .i_psum_top(bias_acc),
    .o_c_bottom(c_bottom)
);
 
genvar c;
generate
    for (c = 0; c < N; c = c + 1) begin : g_lane
        localparam int DELAY = N - 1 - c;
 
        logic signed [ACC_W-1:0] c_lane;
        logic signed [OUT_W-1:0] c_out;
 
        assign bias_acc[c*ACC_W +: ACC_W] = ACC_W'($signed(bias_q[c*BIAS_W +: BIAS_W]));
 
        if (DELAY == 0) begin : g_direct
            assign c_lane = $signed(c_bottom[c*ACC_W +: ACC_W]);
        end else begin : g_delay
            logic signed [DELAY-1:0][ACC_W-1:0] dly_q;
            always_ff @(posedge i_clk) begin
                dly_q[0] <= $signed(c_bottom[c*ACC_W +: ACC_W]);
                for (int k = 1; k < DELAY; k = k + 1) begin
                    dly_q[k] <= dly_q[k-1];
                end
            end
            assign c_lane = dly_q[DELAY-1];
        end
 
        postproc #(
            .ACC_W(ACC_W), .MULT_W(MULT_W), .Q_W(Q_W), .OUT_W(OUT_W), .SHIFT_W(SHIFT_W)
        ) u_pp (
            .i_clk     (i_clk),
            .i_relu_en (i_relu_en),
            .i_quant_en(i_quant_en),
            .i_data    (c_lane),
            .i_mult    (i_mult),
            .i_shift   (i_shift),
            .o_data    (c_out)
        );
 
        assign o_c_data[c*OUT_W +: OUT_W] = c_out;
    end
endgenerate
 
endmodule
`default_nettype wire
