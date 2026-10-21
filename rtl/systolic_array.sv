`default_nettype none
module systolic_array #(
    parameter int N = 8,
    parameter int DW = 8,
    parameter int OUT_W = 32,
    // internal
    parameter int ACC_W = 2*DW + $clog2(N),
    parameter int LAT = 2*N,
    parameter int WCNT_W = (N > 1) ? $clog2(N) : 1
)(
    input wire i_clk,
    input wire i_rstn,
    
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

typedef enum logic { S_RUN = 1'b0, S_LOAD_W = 1'b1 } state_t;
state_t state_q, next_state;

logic [WCNT_W-1:0] w_cnt_q;
logic w_loaded_q, next_w_loaded;
logic load_pend_q, next_load_pend;
logic done_q, next_done;

logic [LAT-1:0] vvalid_q; // valid per pipe
logic [LAT-1:0] vlast_q;

logic stall, pipe_busy, adv;
logic a_fire, w_fire, w_last, m_fire, load_go;

assign pipe_busy = |vvalid_q;
assign stall = m_axis_c_tvalid && !m_axis_c_tready; // freze pipeling
assign load_go = load_pend_q && (state_q == S_RUN) && !pipe_busy;

assign s_axis_w_tready = (state_q == S_LOAD_W);
assign s_axis_a_tready = (state_q == S_RUN) && w_loaded_q && !load_pend_q && !stall;

assign w_fire = s_axis_w_tvalid && s_axis_w_tready;
assign a_fire = s_axis_a_tvalid && s_axis_a_tready;
assign m_fire = m_axis_c_tvalid && m_axis_c_tready;
assign w_last = w_fire && (w_cnt_q == WCNT_W'(N-1));

assign adv = !stall && (pipe_busy || a_fire); // advance cycle while working

logic clk_w, clk_adv;
OPENROAD_CLKGATE u_cg_w (.CK(i_clk), .E(w_fire), .GCK(clk_w));
OPENROAD_CLKGATE u_cg_adv (.CK(i_clk), .E(adv), .GCK(clk_adv));

always_comb begin
    next_state = state_q;
    unique case (state_q)
        S_RUN: if (load_go) next_state = S_LOAD_W;
        S_LOAD_W: if (w_last) next_state = S_RUN;
    endcase
end

always_ff @(posedge i_clk or negedge i_rstn) begin
    if (!i_rstn) begin
        state_q <= S_RUN;
    end else begin
        state_q <= next_state;
    end
end

always_comb begin
    next_w_loaded = w_loaded_q;
    if (load_go) begin
        next_w_loaded = 1'b0;
    end else if (w_last) begin
        next_w_loaded = 1'b1;
    end
end

// ignore request while loading
assign next_load_pend = ((load_pend_q || (i_load_w && state_q == S_RUN)) && !load_go);
assign next_done = (m_fire && m_axis_c_tlast) || w_last;

always_ff @(posedge i_clk or negedge i_rstn) begin
    if (!i_rstn) begin
        w_cnt_q <= '0;
        w_loaded_q <= 1'b0;
        load_pend_q <= 1'b0;
        done_q <= 1'b0;
    end else begin
        w_loaded_q <= next_w_loaded;
        load_pend_q <= next_load_pend;
        done_q <= next_done;
        if (w_last) begin
            w_cnt_q <= '0;
        end else if (w_fire) begin
            w_cnt_q <= w_cnt_q + 1'b1;
        end
    end
end

assign o_busy = (state_q == S_LOAD_W) || load_pend_q || pipe_busy;
assign o_done = done_q;
assign o_weights_loaded = w_loaded_q;

// valid and tlast pipe
always_ff @(posedge i_clk or negedge i_rstn) begin
    if (!i_rstn) begin
        vvalid_q <= '0;
        vlast_q <= '0;
    end else if (adv) begin
        vvalid_q <= {vvalid_q[LAT-2:0], a_fire};
        vlast_q <= {vlast_q[LAT-2:0], a_fire && s_axis_a_tlast};
    end
end

assign m_axis_c_tvalid = vvalid_q[LAT-1];
assign m_axis_c_tlast = vlast_q[LAT-1];


// input skew
logic [N*DW-1:0] a_in;
logic signed [N*DW-1:0] a_left;

assign a_in = a_fire ? s_axis_a_tdata : '0;

genvar r;
generate
    for (r=0; r<N; r=r+1) begin : gen_skew
        logic signed [DW-1:0] sr_q [0:r];

        always_ff @(posedge clk_adv) begin
            if (adv) begin
                sr_q[0] <= a_in[r*DW +: DW];
                for (int k=1; k<=r; k=k+1) begin
                    sr_q[k] <= sr_q[k-1];
                end
            end
        end
        assign a_left[r*DW +: DW] = sr_q[r];
    end
endgenerate

logic signed [N*ACC_W-1:0] c_bottom;

array #( .N(N), .DW(DW), .ACC_W(ACC_W) ) u_array (
    .i_clk_w     (clk_w),
    .i_clk_adv   (clk_adv),
    .i_rstn      (i_rstn),
    .i_w_top     (s_axis_w_tdata),
    .i_a_left    (a_left),
    .o_c_bottom  (c_bottom)
);

// output deskew
genvar c;
generate
    for (c=0; c<N; c=c+1) begin : gen_dskew
        localparam int DELAY = N - 1 - c;
        logic signed [ACC_W-1:0] c_lane;
        
        if (DELAY==0) begin : gen_direct
            assign c_lane = c_bottom[c*ACC_W +: ACC_W];
        end else begin : gen_delay
            logic signed [ACC_W-1:0] dly_q [0:DELAY-1];
            
            always_ff @(posedge clk_adv) begin
                if (adv) begin
                    dly_q[0] <= c_bottom[c*ACC_W +: ACC_W];
                    for (int k=1; k<DELAY; k=k+1) begin
                        dly_q[k] <= dly_q[k-1];
                    end
                end
            end
            assign c_lane = dly_q[DELAY-1];
        end
        assign m_axis_c_tdata[c*OUT_W +: OUT_W] = OUT_W'(c_lane);
    end
endgenerate

endmodule
`default_nettype wire
