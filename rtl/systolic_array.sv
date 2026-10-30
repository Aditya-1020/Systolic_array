`default_nettype none
module systolic_array #(
    parameter int N = 8,
    parameter int DW = 8,
    parameter int OUT_W = 32,
    parameter int ACC_W = 2*DW + ((N>1) ? $clog2(N) : 1)
)(
    input wire i_clk,
    input wire i_rstn,
    input wire signed [N*OUT_W-1:0] i_bias,
    input logic i_load_w,
    output logic o_busy,
    output logic o_done,
    output logic o_weights_loaded,
    
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
localparam int WCNT_W = (N>1) ? $clog2(N) : 1;

typedef enum logic [1:0] {
    S_WAIT_W,
    S_RUN,
    S_DRAIN,
    S_LOAD_W
} state_t;
state_t state_q;
logic [WCNT_W-1:0] w_cnt_q;
logic [LAT-1:0] vvalid_q, vlast_q;
logic done_q, stall, pipe_busy, advance;
logic a_fire, w_fire, w_last, m_fire;
logic clk_w, clk_adv;

assign pipe_busy = |vvalid_q;
assign stall = m_axis_c_tvalid && !m_axis_c_tready;
assign s_axis_w_tready = (state_q == S_LOAD_W);
assign s_axis_a_tready = (state_q == S_RUN) && !i_load_w && !stall;

assign a_fire = s_axis_a_tvalid && s_axis_a_tready;
assign w_fire = s_axis_w_tvalid && s_axis_w_tready;
assign w_last = w_fire && (w_cnt_q == WCNT_W'(N-1));
assign m_fire = m_axis_c_tvalid && m_axis_c_tready;
assign advance = !stall && (pipe_busy || a_fire);

OPENROAD_CLKGATE u_cg_w (.CK(i_clk), .E(w_fire), .GCK(clk_w));
OPENROAD_CLKGATE u_cg_adv (.CK(i_clk), .E(advance), .GCK(clk_adv));

always_ff @(posedge i_clk) begin
    if (!i_rstn) begin
        state_q <= S_WAIT_W;
        w_cnt_q <= '0;
        done_q <= 1'b0;
    end else begin
        done_q <= m_fire && m_axis_c_tlast;
        
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

assign o_busy = (state_q == S_DRAIN) || (state_q == S_LOAD_W) || pipe_busy;
assign o_done = done_q;
assign o_weights_loaded = (state_q == S_RUN);

always_ff @(posedge clk_adv) begin
    if (!i_rstn) begin
        vvalid_q <= '0;
        vlast_q <= '0;
    end else begin
        vvalid_q <= {vvalid_q[LAT-2:0], a_fire};
        vlast_q <= {vlast_q[LAT-2:0], a_fire && s_axis_a_tlast};
    end
end

assign m_axis_c_tvalid = vvalid_q[LAT-1];
assign m_axis_c_tlast = vlast_q[LAT-1];

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
        logic signed [ACC_W-1:0] c_lane;

        assign bias_acc[c*ACC_W +: ACC_W] = $signed(i_bias[c*OUT_W +: ACC_W]);

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
        assign m_axis_c_tdata[c*OUT_W +: OUT_W] = OUT_W'($signed(c_lane));
    end
endgenerate

endmodule
`default_nettype wire
