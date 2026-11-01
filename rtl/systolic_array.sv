`default_nettype none
module systolic_array #(
    parameter int N = 8,
    parameter int DW = 8,
    parameter int OUT_W = 32,
    parameter int MULT_W = 16,
    parameter int Q_W = DW,
    parameter int ACC_W = 2*DW + ((N>1) ? $clog2(N) : 1),
    parameter int SHIFT_W = $clog2(ACC_W + MULT_W + 1)
)(
    input wire i_clk,
    input wire i_rstn,

    input logic i_arr_en,
    input logic i_auto_gate_en, // 0: clk_pp follows advance even when not requantizing
    input logic i_start, // pulse: capture post-process config
    input logic i_load_w, // pulse: start weight load
    input logic i_abort, // pulse
    input logic i_soft_rst, // pulse

    input logic i_relu_en,
    input logic i_quant_en,
    input logic [MULT_W-2:0] i_mult,
    input logic [SHIFT_W-1:0] i_shift,
    input logic signed [N*OUT_W-1:0] i_bias,

    output logic o_busy,
    output logic o_weights_loaded,
    output logic o_stalled,
    output logic o_quant_en, // captured, valid after i_start
    output logic o_clk_w_en, // ICG enables, for LP_STATUS
    output logic o_clk_adv_en,
    output logic o_clk_pp_en,

    input logic s_axis_w_tvalid,
    input logic [N*DW-1:0] s_axis_w_tdata,
    output logic s_axis_w_tready,

    input logic s_axis_a_tvalid,
    input logic [N*DW-1:0] s_axis_a_tdata,
    input logic s_axis_a_tlast,
    output logic s_axis_a_tready,

    input logic m_axis_c_tready,
    output logic m_axis_c_tvalid,
    output logic [N*OUT_W-1:0] m_axis_c_tdata,
    output logic m_axis_c_tlast
);
localparam int LAT = 2*N + 1;
localparam int PP_LAT = 3;
localparam int LAT_PP = LAT + PP_LAT;
localparam int WCNT_W = (N>1) ? $clog2(N) : 1;

typedef enum logic [1:0] {
    S_WAIT_W,
    S_RUN,
    S_DRAIN,
    S_LOAD_W
} state_t;
state_t state_q;
logic [WCNT_W-1:0] w_cnt_q;

// captured config (stable from i_start until next i_start)
logic relu_en_q, quant_en_q;
logic [MULT_W-2:0] mult_q;
logic [SHIFT_W-1:0] shift_q;

logic [LAT_PP-1:0] vvalid_q, vlast_q, vvalid_d, vlast_d;
logic stall, pipe_busy, advance, pp_adv, flush;
logic a_fire, w_fire, w_last;
logic clk_w, clk_adv, clk_pp;

assign flush = i_abort || i_soft_rst;
assign o_quant_en = quant_en_q;

assign pipe_busy = |vvalid_q;
assign stall = m_axis_c_tvalid && !m_axis_c_tready;
assign s_axis_w_tready = (state_q == S_LOAD_W) && i_arr_en;
assign s_axis_a_tready = (state_q == S_RUN) && i_arr_en && !stall;

assign a_fire = s_axis_a_tvalid && s_axis_a_tready;
assign w_fire = s_axis_w_tvalid && s_axis_w_tready;
assign w_last = w_fire && (w_cnt_q == WCNT_W'(N-1));
assign advance = i_arr_en && !stall && (pipe_busy || a_fire);
assign pp_adv = advance && quant_en_q;

assign o_clk_w_en = w_fire;
assign o_clk_adv_en = advance;
assign o_clk_pp_en = i_auto_gate_en ? pp_adv : advance;
assign o_stalled = stall;

OPENROAD_CLKGATE u_cg_w (.CK(i_clk), .E(o_clk_w_en), .GCK(clk_w));
OPENROAD_CLKGATE u_cg_adv (.CK(i_clk), .E(o_clk_adv_en), .GCK(clk_adv));
OPENROAD_CLKGATE u_cg_pp (.CK(i_clk), .E(o_clk_pp_en), .GCK(clk_pp));

// config capture
always_ff @(posedge i_clk) begin
    if (!i_rstn) begin
        relu_en_q <= 1'b0;
        quant_en_q <= 1'b0;
    end else if (i_start) begin
        relu_en_q <= i_relu_en;
        quant_en_q <= i_quant_en;
    end
end

always_ff @(posedge i_clk) begin
    if (i_start) begin
        mult_q <= i_mult;
        shift_q <= i_shift;
    end
end

always_ff @(posedge i_clk) begin
    if (!i_rstn) begin
        state_q <= S_WAIT_W;
        w_cnt_q <= '0;
    end else begin
        if (i_soft_rst) begin
            w_cnt_q <= '0;
            state_q <= S_WAIT_W;
        end else if (i_abort) begin
            w_cnt_q <= '0;
            unique case (state_q)
                S_DRAIN: state_q <= S_RUN;
                S_LOAD_W: state_q <= S_WAIT_W;
                default: ;
            endcase
        end else begin
            unique case (state_q)
                S_WAIT_W: begin
                    if (i_load_w) begin
                        w_cnt_q <= '0;
                        state_q <= S_LOAD_W;
                    end
                end
                S_RUN: begin
                    if (i_load_w) begin
                        w_cnt_q <= '0;
                        if (pipe_busy) begin
                            state_q <= S_DRAIN;
                        end else begin
                            state_q <= S_LOAD_W;
                        end
                    end
                end

                S_DRAIN: begin
                    if (!pipe_busy) begin
                        state_q <= S_LOAD_W;
                    end
                end

                S_LOAD_W: begin
                    if (w_last) begin
                        w_cnt_q <= '0;
                        state_q <= S_RUN;
                    end else if (w_fire) begin
                        w_cnt_q <= w_cnt_q + 1'b1;
                    end
                end
                default: state_q <= S_WAIT_W;
            endcase
        end
    end
end

assign o_busy = (state_q == S_DRAIN) || (state_q == S_LOAD_W) || pipe_busy;
assign o_weights_loaded = (state_q == S_RUN);

assign vvalid_d = {vvalid_q[LAT_PP-2:LAT], vvalid_q[LAT-1] && quant_en_q, vvalid_q[LAT-2:0], a_fire};
assign vlast_d = {vlast_q[LAT_PP-2:LAT], vlast_q[LAT-1] && quant_en_q, vlast_q[LAT-2:0], a_fire && s_axis_a_tlast};

always_ff @(posedge i_clk) begin
    if (!i_rstn || flush) begin
        vvalid_q <= '0;
        vlast_q <= '0;
    end else if (advance) begin
        vvalid_q <= vvalid_d;
        vlast_q <= vlast_d;
    end
end

assign m_axis_c_tvalid = i_arr_en && (quant_en_q ? vvalid_q[LAT_PP-1] : vvalid_q[LAT-1]);
assign m_axis_c_tlast = quant_en_q ? vlast_q[LAT_PP-1] : vlast_q[LAT-1];

logic [N*DW-1:0] a_in, a_left;
logic [N*ACC_W-1:0] c_bottom, bias_acc;

assign a_in = a_fire ? s_axis_a_tdata : '0;

genvar r;
generate
    for (r =0; r < N; r=r+1) begin : gen_skew
        logic signed [r:0][DW-1:0] sr_q;
        always_ff @(posedge clk_adv) begin
            sr_q[0] <= a_in[r*DW +: DW];
            for (int k=1; k<=r; k=k+1) begin
                sr_q[k] <= sr_q[k-1];
            end
        end
        assign a_left[r*DW +: DW] = sr_q[r];
    end
endgenerate

array #(.N(N), .DW(DW), .ACC_W(ACC_W)) u_array (
    .i_clk_w   (clk_w),
    .i_clk_adv (clk_adv),
    .i_w_stream(s_axis_w_tdata),
    .i_a_left  (a_left),
    .i_psum_top(bias_acc),
    .o_c_bottom(c_bottom)
);

genvar c;
generate
    for (c =0;c<N; c=c+1) begin : gen_output
        localparam int DELAY = N-1-c;
        localparam logic signed [OUT_W-1:0] BIAS_MAX = (OUT_W'(1) << (ACC_W-2)) - OUT_W'(1);
        localparam logic signed [OUT_W-1:0] BIAS_MIN = -(OUT_W'(1) << (ACC_W-2));

        logic signed [OUT_W-1:0] bias_in;
        logic signed [ACC_W-1:0] c_lane;
        logic signed [OUT_W-1:0] c_out;

        assign bias_in = i_bias[c*OUT_W +: OUT_W];
        assign bias_acc[c*ACC_W +: ACC_W] = (bias_in > BIAS_MAX) ? ACC_W'(BIAS_MAX) : (bias_in < BIAS_MIN) ? ACC_W'(BIAS_MIN) : bias_in[ACC_W-1:0];

        if (DELAY == 0) begin : gen_direct
            assign c_lane = $signed(c_bottom[c*ACC_W +: ACC_W]);
        end else begin : gen_delay
            logic signed [DELAY-1:0][ACC_W-1:0] dly_q;
            always_ff @(posedge clk_adv) begin
                dly_q[0] <= $signed(c_bottom[c*ACC_W +: ACC_W]);
                for (int k = 1; k<DELAY; k=k+1) begin
                    dly_q[k] <= dly_q[k-1];
                end
            end
            assign c_lane = dly_q[DELAY-1];
        end

        postproc #(
            .ACC_W(ACC_W), .MULT_W(MULT_W), .Q_W(Q_W),
            .OUT_W(OUT_W), .SHIFT_W(SHIFT_W)
        ) u_pp (
            .i_clk      (clk_pp),
            .i_relu_en  (relu_en_q),
            .i_quant_en (quant_en_q),
            .i_data     (c_lane),
            .i_mult     (mult_q),
            .i_shift    (shift_q),
            .o_data     (c_out)
        );

        assign m_axis_c_tdata[c*OUT_W +: OUT_W] = c_out;
    end
endgenerate

endmodule
`default_nettype wire
