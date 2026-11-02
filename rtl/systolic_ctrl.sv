`default_nettype none
module systolic_ctrl #(
    parameter int N = 8,
    parameter int OUT_W = 32,
    parameter int Q_W = 8,
    parameter int BIAS_W = 16,
    parameter int MEM_DW = 64,
    parameter int W_DEPTH = 256,
    parameter int A_DEPTH = 256,
    parameter int R_DEPTH = 512,
    parameter int W_AW = $clog2(W_DEPTH),
    parameter int A_AW = $clog2(A_DEPTH),
    parameter int R_AW = $clog2(R_DEPTH)
)(
    input wire i_clk,
    input wire i_rstn,
 
    // commands (single-cycle pulses from CSR) and config
    input logic i_load_w,
    input logic i_start,
    input logic i_abort,
    input logic i_quant_en,
    input logic [W_AW-1:0] i_w_addr,
    input logic [A_AW-1:0] i_a_addr,
    input logic [A_AW:0] i_a_count,
    input logic [R_AW-1:0] i_r_addr,
 
    // status
    output logic o_busy,
    output logic o_w_valid,
    output logic o_done, // pulse: last result beat is being written
    output logic o_start_acc, // pulse: START accepted
    output logic o_err_cmd, // pulse
    output logic o_err_cfg, // pulse
 
    // SRAM client ports
    output logic o_w_ce,
    output logic [W_AW-1:0] o_w_addr,
    output logic o_a_ce,
    output logic [A_AW-1:0] o_a_addr,
    output logic o_r_ce, // write-only client
    output logic [R_AW-1:0] o_r_addr,
    output logic [MEM_DW-1:0] o_r_wdata,
 
    // to core
    output logic o_bias_shift,
    output logic o_w_shift,
    output logic o_a_vld,
    output logic o_a_last,
    output logic o_flush,
 
    // from core
    input logic i_c_vld,
    input logic i_c_last,
    input logic [N*OUT_W-1:0] i_c_data
);
 
localparam int BB = (N * BIAS_W) / MEM_DW; // bias beats
localparam int LD_BEATS = BB + N; // beats per weight block
localparam int LDW = $clog2(LD_BEATS + 1);
localparam int NB = (N * OUT_W) / MEM_DW; // raw beats per result row
localparam int OBQ = (N * Q_W) / MEM_DW; // requant beats per result row
localparam int BW = (NB > 1) ? $clog2(NB) : 1;
localparam int CW = 16; // wide intermediate for range checks
 
typedef enum logic [1:0] {
    S_IDLE,
    S_LOAD,
    S_RUN
} state_t;
 
state_t state_q;
 
logic w_valid_q;
logic [LDW-1:0] ld_cnt_q;
logic [A_AW:0] a_left_q;
logic [BW-1:0] phase_q;
logic bias_sh_q, w_sh_q, ld_last_q;
logic a_vld_q, a_last_q;
logic wr_act_q, wr_lastrow_q;
logic [BW-1:0] wr_beat_q;
 
logic [W_AW-1:0] w_ptr_q;
logic [A_AW-1:0] a_ptr_q;
logic [R_AW-1:0] r_ptr_q;
logic [N*OUT_W-1:0] row_q;
 
logic idle, cmd_req, legal, cfg_bad_ld, cfg_bad_st, cfg_bad, acc_ld, acc_st;
logic [CW-1:0] wr_total;
 
assign idle = (state_q == S_IDLE);
assign cmd_req = !i_abort && (i_load_w || i_start);
assign legal = idle && !(i_load_w && i_start) && (!i_start || w_valid_q);
 
assign wr_total = CW'(i_a_count) * (i_quant_en ? CW'(OBQ) : CW'(NB));
assign cfg_bad_ld = (CW'(i_w_addr) + CW'(LD_BEATS)) > CW'(W_DEPTH);
assign cfg_bad_st = (i_a_count == '0) || ((CW'(i_a_addr) + CW'(i_a_count)) > CW'(A_DEPTH)) || ((CW'(i_r_addr) + wr_total) > CW'(R_DEPTH));
assign cfg_bad = i_load_w ? cfg_bad_ld : cfg_bad_st;
 
assign acc_ld = cmd_req && legal && !cfg_bad && i_load_w;
assign acc_st = cmd_req && legal && !cfg_bad && i_start;
assign o_start_acc = acc_st;
assign o_err_cmd = cmd_req && !legal;
assign o_err_cfg = cmd_req && legal && cfg_bad;
 
logic ld_issue, a_issue;
logic [BW-1:0] pace_m1;
 
assign pace_m1 = i_quant_en ? BW'(0) : BW'(NB - 1);
assign ld_issue = (state_q == S_LOAD) && (ld_cnt_q != LDW'(LD_BEATS));
assign a_issue = (state_q == S_RUN) && (a_left_q != '0) && (phase_q == '0);
 
assign o_w_ce = ld_issue;
assign o_w_addr = w_ptr_q;
assign o_a_ce = a_issue;
assign o_a_addr = a_ptr_q;
 
assign o_bias_shift = bias_sh_q;
assign o_w_shift = w_sh_q;
assign o_a_vld = a_vld_q;
assign o_a_last = a_last_q;
assign o_flush = i_abort;
 
logic [BW-1:0] last_beat;
logic wr_beat_last;
logic [N*Q_W-1:0] q_pack;
logic [N*OUT_W-1:0] row_in;
 
assign last_beat = i_quant_en ? BW'(OBQ - 1) : BW'(NB - 1);
assign wr_beat_last = (wr_beat_q == last_beat);
 
genvar c;
generate
    for (c = 0; c < N; c = c + 1) begin : g_pack
        assign q_pack[c*Q_W +: Q_W] = i_c_data[c*OUT_W +: Q_W];
    end
endgenerate
 
assign row_in = i_quant_en ? (N*OUT_W)'(q_pack) : i_c_data;
 
assign o_r_ce = wr_act_q;
assign o_r_addr = r_ptr_q;
assign o_r_wdata = row_q[wr_beat_q*MEM_DW +: MEM_DW];
 
assign o_done = wr_act_q && wr_beat_last && wr_lastrow_q && !i_abort;
 
assign o_busy = (state_q != S_IDLE);
assign o_w_valid = w_valid_q;
 
always_ff @(posedge i_clk) begin
    if (!i_rstn) begin
        state_q <= S_IDLE;
        w_valid_q <= 1'b0;
        ld_cnt_q <= LDW'(LD_BEATS);
        a_left_q <= '0;
        phase_q <= '0;
        bias_sh_q <= 1'b0;
        w_sh_q <= 1'b0;
        ld_last_q <= 1'b0;
        a_vld_q <= 1'b0;
        a_last_q <= 1'b0;
        wr_act_q <= 1'b0;
        wr_lastrow_q <= 1'b0;
        wr_beat_q <= '0;
    end else if (i_abort) begin
        state_q <= S_IDLE; // w_valid_q untouched: already 0 if a load was running
        ld_cnt_q <= LDW'(LD_BEATS);
        a_left_q <= '0;
        phase_q <= '0;
        bias_sh_q <= 1'b0;
        w_sh_q <= 1'b0;
        ld_last_q <= 1'b0;
        a_vld_q <= 1'b0;
        a_last_q <= 1'b0;
        wr_act_q <= 1'b0;
        wr_beat_q <= '0;
    end else begin
        bias_sh_q <= 1'b0;
        w_sh_q <= 1'b0;
        ld_last_q <= 1'b0;
        a_vld_q <= 1'b0;
        a_last_q <= 1'b0;
 
        if (acc_ld) begin
            state_q <= S_LOAD;
            w_valid_q <= 1'b0;
            ld_cnt_q <= '0;
        end
 
        if (acc_st) begin
            state_q <= S_RUN;
            a_left_q <= i_a_count;
            phase_q <= '0;
        end
 
        if (ld_issue) begin
            ld_cnt_q <= ld_cnt_q + LDW'(1);
            bias_sh_q <= (ld_cnt_q < LDW'(BB));
            w_sh_q <= (ld_cnt_q >= LDW'(BB));
            ld_last_q <= (ld_cnt_q == LDW'(LD_BEATS - 1));
        end
        if (ld_last_q) begin
            w_valid_q <= 1'b1;
            state_q <= S_IDLE;
        end
 
        // RUN: issue side
        if (a_left_q != '0) begin
            phase_q <= (phase_q == pace_m1) ? '0 : (phase_q + BW'(1));
        end
        if (a_issue) begin
            a_left_q <= a_left_q - (A_AW+1)'(1);
            a_vld_q <= 1'b1;
            a_last_q <= (a_left_q == (A_AW+1)'(1));
        end
 
        // RUN: write side
        if (i_c_vld) begin
            wr_act_q <= 1'b1;
            wr_beat_q <= '0;
            wr_lastrow_q <= i_c_last;
        end else if (wr_act_q) begin
            if (wr_beat_last) begin
                wr_act_q <= 1'b0;
            end else begin
                wr_beat_q <= wr_beat_q + BW'(1);
            end
        end
 
        if (o_done) begin
            state_q <= S_IDLE;
        end
    end
end
 
always_ff @(posedge i_clk) begin
    if (acc_ld) begin
        w_ptr_q <= i_w_addr;
    end else if (ld_issue) begin
        w_ptr_q <= w_ptr_q + W_AW'(1);
    end
 
    if (acc_st) begin
        a_ptr_q <= i_a_addr;
        r_ptr_q <= i_r_addr;
    end else begin
        if (a_issue) begin
            a_ptr_q <= a_ptr_q + A_AW'(1);
        end
        if (wr_act_q) begin
            r_ptr_q <= r_ptr_q + R_AW'(1);
        end
    end
 
    if (i_c_vld) begin
        row_q <= row_in;
    end
end
 
endmodule
`default_nettype wire
