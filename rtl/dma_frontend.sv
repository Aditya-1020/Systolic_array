/*
* DMA Expects:
    * [READ] Request: {VALID, READY, aDDR}, Response: {VALID, READY, DATA, ERROR}
    * [WRITE] Request: {VALID, READY, ADDR, DATA, STRB}; Response: {VALID, READY, ERROR}
* Timing conract:
    * req_ready, rsp_valid, rsp_data, rsp_err: drive from flops
    * Only legal comb path: mem_wr_req_ready -> mem_rd_rsp_ready (array stall)
    * do not drive rsp_valid from rsp_ready in same cycle
    * response order  = requst order
    * after rd_err/wr_err one extra req can issue
*/
`default_nettype none
module dma_frontend #(
    parameter int N = 8,
    parameter int DW = 8,
    parameter int OUT_W = 32,
    parameter int Q_W = DW,
    parameter int ADDR_W = 32,
    parameter int MEM_DW = N*DW,
    parameter int MAX_RD_OUT = 4,
    parameter int MAX_WR_OUT = 4
)(
    input wire i_clk,
    input wire i_rstn,

    input logic i_load_weights,
    input logic i_start,
    input logic i_abort,
    input logic i_soft_reset,

    input logic i_arr_en,
    input logic i_bias_en,
    input logic [ADDR_W-1:0] i_bias_base,
    input logic [ADDR_W-1:0] i_weight_base,
    input logic [ADDR_W-1:0] i_act_base,
    input logic [ADDR_W-1:0] i_dst_base,
    input logic [31:0] i_act_count,

    output logic o_busy,
    output logic o_computing,
    output logic o_done,
    output logic o_err_read,
    output logic o_err_write,
    output logic o_err_cfg,
    output logic o_err_cmd,

    output logic o_arr_load_w,
    output logic o_arr_start,
    output logic o_arr_abort,
    output logic o_arr_soft_rst,
    output logic signed [N*OUT_W-1:0] o_bias,
    input logic i_weights_loaded,
    input logic i_quant_en_q,

    output logic mem_rd_req_valid,
    input logic mem_rd_req_ready,
    output logic [ADDR_W-1:0] mem_rd_req_addr,

    input logic mem_rd_rsp_valid,
    output logic mem_rd_rsp_ready,
    input logic [MEM_DW-1:0] mem_rd_rsp_data,
    input logic mem_rd_rsp_error,

    output logic mem_wr_req_valid,
    input logic mem_wr_req_ready,
    output logic [ADDR_W-1:0] mem_wr_req_addr,
    output logic [MEM_DW-1:0] mem_wr_req_data,
    output logic [(MEM_DW/8)-1:0] mem_wr_req_strb,

    input logic mem_wr_rsp_valid,
    output logic mem_wr_rsp_ready,
    input logic mem_wr_rsp_error,

    output logic s_axis_w_tvalid,
    output logic [N*DW-1:0] s_axis_w_tdata,
    input logic s_axis_w_tready,

    output logic s_axis_a_tvalid,
    output logic [N*DW-1:0] s_axis_a_tdata,
    output logic s_axis_a_tlast,
    input logic s_axis_a_tready,

    input logic m_axis_c_tvalid,
    input logic [N*OUT_W-1:0] m_axis_c_tdata,
    input logic m_axis_c_tlast,
    output logic m_axis_c_tready
);

localparam int BEAT_BYTES = MEM_DW/8;
localparam int AL_W = (BEAT_BYTES > 1) ? $clog2(BEAT_BYTES) : 1;
localparam int NB = (N*OUT_W)/MEM_DW;
localparam int OB_Q = (N*Q_W)/MEM_DW;
localparam int OBW = (NB > 1) ? $clog2(NB) : 1;
localparam int RD_CNT_W = (MAX_RD_OUT > 1) ? $clog2(MAX_RD_OUT+1) : 1;
localparam int WR_CNT_W = (MAX_WR_OUT > 1) ? $clog2(MAX_WR_OUT+1) : 1;

localparam logic [31:0] WEIGHT_BEATS = N;
localparam logic [31:0] LOAD_BEATS = N + NB;
localparam logic [RD_CNT_W-1:0] MAX_RD_OUT_U = RD_CNT_W'(MAX_RD_OUT);
localparam logic [WR_CNT_W-1:0] MAX_WR_OUT_U = WR_CNT_W'(MAX_WR_OUT);

typedef enum logic [1:0] {
    S_IDLE,
    S_LOAD,
    S_RUN,
    S_FLUSH
} state_t;
state_t state_q;

logic [ADDR_W-1:0] rd_ptr_q, wt_base_q, dst_ptr_q;
logic [31:0] req_left_q, rsp_left_q;
logic [RD_CNT_W-1:0] rd_out_q;
logic [WR_CNT_W-1:0] wr_out_q;
logic [OBW-1:0] wbeat_q;
logic last_sent_q, quant_en_q;
logic signed [N*OUT_W-1:0] bias_q;
logic flush_cmd, flush_req, rd_err, wr_err;
logic cmd_req, cmd_legal, cmd_cfg_bad, load_acc, start_acc;
logic rd_req_fire, rd_rsp_fire, wr_req_fire;
logic rsp_is_bias, rd_last_bias_req, bias_push;
logic wbeat_last, done_cond;
logic mem_rd_rsp_HS, mem_wr_rsp_HS, cmd_accept;

assign flush_cmd = i_abort || i_soft_reset;
assign cmd_req = !flush_cmd && (i_load_weights || i_start);

assign cmd_legal = (state_q == S_IDLE) && i_arr_en && !(i_load_weights && i_start) && (!i_start || i_weights_loaded);
assign cmd_cfg_bad = (i_load_weights && ((|i_weight_base[AL_W-1:0]) || (i_bias_en && (|i_bias_base[AL_W-1:0])))) ||
                     (i_start && ((i_act_count == 32'd0) || (|i_act_base[AL_W-1:0]) || (|i_dst_base[AL_W-1:0])));

assign cmd_accept = cmd_req && cmd_legal && !cmd_cfg_bad;

assign load_acc = cmd_accept && i_load_weights;
assign start_acc = cmd_accept && i_start;

assign o_err_cmd = cmd_req && !cmd_legal;
assign o_err_cfg = cmd_req && cmd_legal && cmd_cfg_bad;
assign o_arr_load_w = load_acc;
assign o_arr_start = start_acc;

assign mem_rd_rsp_HS = mem_rd_rsp_valid && mem_rd_rsp_ready;
assign mem_wr_rsp_HS = mem_wr_rsp_valid && mem_wr_rsp_ready;

assign rd_rsp_fire = mem_rd_rsp_HS;

assign rd_err = mem_rd_rsp_HS && mem_rd_rsp_error;
assign wr_err = mem_wr_rsp_HS && mem_wr_rsp_error;

assign o_err_read = rd_err;
assign o_err_write = wr_err;

assign flush_req = flush_cmd || rd_err || wr_err;
assign o_arr_abort = flush_req;
assign o_arr_soft_rst = i_soft_reset;

assign mem_rd_req_valid = ((state_q == S_LOAD) || (state_q == S_RUN)) && (req_left_q != 32'd0) && (rd_out_q < MAX_RD_OUT_U) && !flush_cmd;

assign mem_rd_req_addr = rd_ptr_q;
assign rd_req_fire = mem_rd_req_valid && mem_rd_req_ready;
assign rsp_is_bias = (state_q == S_LOAD) && (rsp_left_q > WEIGHT_BEATS);
assign rd_last_bias_req = (state_q == S_LOAD) && (req_left_q == (WEIGHT_BEATS + 32'd1));
assign bias_push = rsp_is_bias && rd_rsp_fire && !mem_rd_rsp_error;

always_comb begin
    unique case (state_q)
        S_LOAD: mem_rd_rsp_ready = rsp_is_bias ? 1'b1 : s_axis_w_tready;
        S_RUN: mem_rd_rsp_ready = s_axis_a_tready;
        default: mem_rd_rsp_ready = 1'b1;
    endcase
end

assign s_axis_w_tvalid = (state_q == S_LOAD) && !rsp_is_bias && mem_rd_rsp_valid && !mem_rd_rsp_error;
assign s_axis_w_tdata = mem_rd_rsp_data;

assign s_axis_a_tvalid = (state_q == S_RUN) && mem_rd_rsp_valid && !mem_rd_rsp_error;
assign s_axis_a_tdata = mem_rd_rsp_data;
assign s_axis_a_tlast = (state_q == S_RUN) && (rsp_left_q == 32'd1);

logic [N*Q_W-1:0] q_pack;
logic [N*OUT_W-1:0] out_flat;
logic [NB-1:0][MEM_DW-1:0] out_beats;

genvar c;
generate
    for (c = 0; c < N; c = c+1) begin : gen_pack
        assign q_pack[c*Q_W +: Q_W] = m_axis_c_tdata[c*OUT_W +: Q_W];
    end
endgenerate

assign out_flat = quant_en_q ? (N*OUT_W)'(q_pack) : m_axis_c_tdata;
assign out_beats = out_flat;
assign wbeat_last = (wbeat_q == (quant_en_q ? OBW'(OB_Q-1) : OBW'(NB-1)));
assign mem_wr_req_valid = (state_q == S_RUN) && m_axis_c_tvalid && (wr_out_q < MAX_WR_OUT_U) && !flush_cmd;
assign mem_wr_req_addr = dst_ptr_q;
assign mem_wr_req_data = out_beats[wbeat_q];
assign mem_wr_req_strb = '1;
assign wr_req_fire = mem_wr_req_valid && mem_wr_req_ready;
assign m_axis_c_tready = wr_req_fire && wbeat_last;
assign mem_wr_rsp_ready = 1'b1;

assign done_cond = (state_q == S_RUN) && last_sent_q && (wr_out_q == '0);

assign o_done = done_cond && !flush_req;
assign o_busy = (state_q != S_IDLE);
assign o_computing = (state_q == S_RUN);
assign o_bias = bias_q;

always_ff @(posedge i_clk) begin
    if (!i_rstn) begin
        state_q <= S_IDLE;
        req_left_q <= '0;
        rsp_left_q <= '0;
        rd_out_q <= '0;
        wr_out_q <= '0;
        wbeat_q <= '0;
        last_sent_q <= 1'b0;
        quant_en_q <= 1'b0;
    end else begin
        rd_out_q <= rd_out_q + RD_CNT_W'(rd_req_fire) - RD_CNT_W'(rd_rsp_fire);
        wr_out_q <= wr_out_q + WR_CNT_W'(wr_req_fire) - WR_CNT_W'(mem_wr_rsp_HS);

        if (start_acc)
            quant_en_q <= i_quant_en_q;

        if (flush_req) begin
            state_q <= S_FLUSH;
            req_left_q <= '0;
            rsp_left_q <= '0;
            wbeat_q <= '0;
            last_sent_q <= 1'b0;
        end else begin
            unique case (state_q)
                S_IDLE: begin
                    if (load_acc) begin
                        state_q <= S_LOAD;
                        req_left_q <= i_bias_en ? LOAD_BEATS : WEIGHT_BEATS;
                        rsp_left_q <= i_bias_en ? LOAD_BEATS : WEIGHT_BEATS;
                    end else if (start_acc) begin
                        state_q <= S_RUN;
                        req_left_q <= i_act_count;
                        rsp_left_q <= i_act_count;
                        wbeat_q <= '0;
                        last_sent_q <= 1'b0;
                    end
                end

                S_LOAD: begin
                    if (rd_req_fire)
                        req_left_q <= req_left_q - 32'd1;

                    if (rd_rsp_fire)
                        rsp_left_q <= rsp_left_q - 32'd1;

                    if (rsp_left_q == 32'd0)
                        state_q <= S_IDLE;
                end

                S_RUN: begin
                    if (rd_req_fire)
                        req_left_q <= req_left_q - 32'd1;

                    if (rd_rsp_fire)
                        rsp_left_q <= rsp_left_q - 32'd1;

                    if (wr_req_fire) begin
                        if (wbeat_last) begin
                            wbeat_q <= '0;
                            if (m_axis_c_tlast)
                                last_sent_q <= 1'b1;
                        end else begin
                            wbeat_q <= wbeat_q + 1'b1;
                        end
                    end

                    if (done_cond)
                        state_q <= S_IDLE;
                end

                S_FLUSH: begin
                    if ((rd_out_q == '0) && (wr_out_q == '0))
                        state_q <= S_IDLE;
                end

                default: state_q <= S_IDLE;
            endcase
        end
    end
end

always_ff @(posedge i_clk) begin
    if (!i_rstn) begin
        rd_ptr_q <= '0;
        wt_base_q <= '0;
        dst_ptr_q <= '0;
    end else if (load_acc) begin
        rd_ptr_q <= i_bias_en ? i_bias_base : i_weight_base;
        wt_base_q <= i_weight_base;
        if (!i_bias_en) begin
            bias_q <= '0;
        end
    end else if (start_acc) begin
        rd_ptr_q <= i_act_base;
        dst_ptr_q <= i_dst_base;
    end else begin
        if (rd_req_fire) begin
            rd_ptr_q <= rd_last_bias_req ? wt_base_q : (rd_ptr_q + ADDR_W'(BEAT_BYTES));
        end

        if (wr_req_fire) begin
            dst_ptr_q <= dst_ptr_q + ADDR_W'(BEAT_BYTES);
        end

        if (bias_push) begin
            bias_q <= {mem_rd_rsp_data, bias_q[N*OUT_W-1:MEM_DW]};
        end
    end
end

endmodule
`default_nettype wire
