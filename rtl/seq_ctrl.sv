`default_nettype none
module seq_ctrl #(
    parameter int N = sys_pkg::p_n,
    parameter int ACC_W = sys_pkg::p_acc_w,
    parameter int SH_W = sys_pkg::p_shift_w,
    parameter int ROW_W = $clog2(sys_pkg::p_max_rows + 1),
    parameter int BEAT_W = $clog2(sys_pkg::p_raw_beats)
) (
    input wire i_clk,
    input wire i_rstn,
    input wire i_start,
    input wire i_w_load_en,
    input wire [15:0] i_waddr,
    input wire [15:0] i_aaddr,
    input wire [15:0] i_caddr,
    input wire [15:0] i_count,
    input wire i_pp_en,
    input wire i_relu_en,
    input wire i_round_en,
    input wire [SH_W-1:0] i_shift,
    output logic o_busy,
    output logic o_run_start,
    output logic o_done_set,
    output logic o_err_set,
    output sys_pkg::ctrl_state_t o_state,
    output logic o_pp_en,
    output logic o_relu_en,
    output logic [SH_W-1:0] o_shift,
    output logic [ACC_W-1:0] o_round_const,
    output logic [sys_pkg::p_rbuf_aw-1:0] o_caddr,
    output logic [ROW_W-1:0] o_count,
    output logic o_wbuf_req,
    output logic [sys_pkg::p_wbuf_macro_aw-1:0] o_wbuf_addr,
    input wire i_wbuf_rvalid,
 
    // ABUF core read port
    output logic o_abuf_req,
    output logic [sys_pkg::p_abuf_aw-1:0] o_abuf_addr,
    input wire i_abuf_rvalid,
    input wire [sys_pkg::p_beat_w-1:0] i_abuf_rdata,
 
    // datapath control
    output logic o_w_load,
    output logic o_a_advance,
    output logic o_a_valid,
    output logic [sys_pkg::p_beat_w-1:0] o_a_data,
    output logic [BEAT_W-1:0] o_beat,
    input wire i_c_valid,
    input wire i_all_written
);
localparam int WL_W = $clog2(N + 1);
localparam int WA_W = sys_pkg::p_wbuf_aw;
localparam int WMA_W = sys_pkg::p_wbuf_macro_aw;
localparam int AA_W = sys_pkg::p_abuf_aw;

sys_pkg::ctrl_state_t state_q, state_d;
sys_pkg::addr_t a_end, c_end, w_end, rbuf_beats;
logic bad_count, bad_abuf, bad_rbuf, bad_wbuf, bad_shift, bad_cfg;
logic accept, start_q, start_pulse;

logic bad_q, w_load_q, pp_en_q, relu_q;
logic [sys_pkg::p_wbuf_aw-1:0] waddr_q;
logic [sys_pkg::p_abuf_aw-1:0] aaddr_q;
logic [sys_pkg::p_rbuf_aw-1:0] caddr_q;
logic [ROW_W-1:0] count_q;
logic [SH_W-1:0] shift_q;
logic [ACC_W-1:0] round_const_q, round_const_d;
logic running, fire, adv_go, adv_d, adv_q;
logic wl_last, rd_last;
logic [WL_W-1:0] wl_cnt_q;
logic [ROW_W-1:0] rd_cnt_q, fire_cnt_q, fire_cnt_nxt;
logic [BEAT_W-1:0] phase_q;
logic [sys_pkg::p_wbuf_aw-1:0] wl_addr;
logic wbuf_pend_q;

assign start_pulse = i_start & ~start_q;
assign accept = start_pulse & (state_q == sys_pkg::ST_IDLE);

always_ff @(posedge i_clk) begin
    if (!i_rstn)
        start_q <= 1'b0;
    else
        start_q <= i_start;
end
assign rbuf_beats = i_pp_en ? sys_pkg::addr_t'(i_count) : (sys_pkg::addr_t'(i_count) * sys_pkg::p_raw_beats);
assign a_end = sys_pkg::addr_t'(i_aaddr) + sys_pkg::addr_t'(i_count);
assign c_end = sys_pkg::addr_t'(i_caddr) + rbuf_beats;
assign w_end = sys_pkg::addr_t'(i_waddr) + sys_pkg::addr_t'(sys_pkg::p_n);
 
assign bad_count = (i_count == 16'd0) | (i_count > 16'(sys_pkg::p_max_rows));
assign bad_abuf = (a_end > sys_pkg::addr_t'(sys_pkg::p_abuf_depth));
assign bad_rbuf = (c_end > sys_pkg::addr_t'(sys_pkg::p_rbuf_depth));
assign bad_wbuf = i_w_load_en & (w_end > sys_pkg::addr_t'(sys_pkg::p_wbuf_depth));
assign bad_shift = i_pp_en & (i_shift > SH_W'(sys_pkg::p_shift_max));
assign bad_cfg = bad_count | bad_abuf | bad_rbuf | bad_wbuf | bad_shift;

assign round_const_d = (i_round_en && (i_shift != '0)) ? (ACC_W'(1) << (i_shift - 1'b1)) : '0;

always_ff @(posedge i_clk) begin
    if (!i_rstn) begin
        bad_q <= 1'b0;
        w_load_q <= 1'b0;
        pp_en_q <= 1'b1;
        relu_q <= 1'b0;
        waddr_q <= '0;
        aaddr_q <= '0;
        caddr_q <= '0;
        count_q <= '0;
        shift_q <= '0;
        round_const_q <= '0;
    end else if (accept) begin
        bad_q <= bad_cfg;
        w_load_q <= i_w_load_en;
        pp_en_q <= i_pp_en;
        relu_q <= i_relu_en;
        waddr_q <= i_waddr[sys_pkg::p_wbuf_aw-1:0];
        aaddr_q <= i_aaddr[sys_pkg::p_abuf_aw-1:0];
        caddr_q <= i_caddr[sys_pkg::p_rbuf_aw-1:0];
        count_q <= i_count[ROW_W-1:0];
        shift_q <= i_shift;
        round_const_q <= round_const_d;
    end
end

assign running = (state_q == sys_pkg::ST_RUN) || (state_q == sys_pkg::ST_FLUSH);
assign fire = adv_q & i_c_valid;
assign fire_cnt_nxt = fire_cnt_q + ROW_W'(fire);
assign adv_go = running & (fire_cnt_nxt < count_q);
assign adv_d = adv_go & (pp_en_q | (phase_q == BEAT_W'(sys_pkg::p_raw_beats - 2)));
 
assign o_abuf_req = adv_d & (rd_cnt_q < count_q);
assign rd_last = o_abuf_req & ((rd_cnt_q + ROW_W'(1)) == count_q);
assign wl_last = (wl_cnt_q == WL_W'(N - 1));
 
always_comb begin
    state_d = state_q;
    case (state_q)
        sys_pkg::ST_IDLE:  if (start_pulse) state_d = sys_pkg::ST_CHECK;
        sys_pkg::ST_CHECK: begin
            if (bad_q) state_d = sys_pkg::ST_IDLE;
            else if (w_load_q) state_d = sys_pkg::ST_WLOAD;
            else state_d = sys_pkg::ST_RUN;
        end
        sys_pkg::ST_WLOAD: if (wl_last) state_d = sys_pkg::ST_RUN;
        sys_pkg::ST_RUN:   if (rd_last) state_d = sys_pkg::ST_FLUSH;
        sys_pkg::ST_FLUSH: if (i_all_written) state_d = sys_pkg::ST_DONE;
        sys_pkg::ST_DONE:  state_d = sys_pkg::ST_IDLE;
        default:           state_d = sys_pkg::ST_IDLE;
    endcase
end
 
assign o_wbuf_req = (state_q == sys_pkg::ST_WLOAD);

always_ff @(posedge i_clk) begin
    if (!i_rstn) begin
        state_q <= sys_pkg::ST_IDLE;
        adv_q <= 1'b0;
        wl_cnt_q <= '0;
        rd_cnt_q <= '0;
        fire_cnt_q <= '0;
        phase_q <= BEAT_W'(sys_pkg::p_raw_beats - 2);
        wbuf_pend_q <= 1'b0;
    end else begin
        state_q <= state_d;
        adv_q <= adv_d;
        wbuf_pend_q <= o_wbuf_req;

        if (state_q == sys_pkg::ST_WLOAD)
            wl_cnt_q <= wl_cnt_q + 1'b1;
        else
            wl_cnt_q <= '0;

        if (running) begin
            if (o_abuf_req)
                rd_cnt_q <= rd_cnt_q + 1'b1;
            fire_cnt_q <= fire_cnt_nxt;
            phase_q <= phase_q + 1'b1;
        end else begin
            rd_cnt_q <= '0;
            fire_cnt_q <= '0;
            phase_q <= BEAT_W'(sys_pkg::p_raw_beats - 2);
        end
    end
end

assign wl_addr = waddr_q + WA_W'(wl_cnt_q);
assign o_wbuf_addr = WMA_W'(wl_addr);
assign o_abuf_addr = aaddr_q + AA_W'(rd_cnt_q);

assign o_w_load = wbuf_pend_q & i_wbuf_rvalid;
assign o_a_advance = adv_q;
assign o_a_valid = i_abuf_rvalid;
assign o_a_data = i_abuf_rdata & {sys_pkg::p_beat_w{i_abuf_rvalid}};
assign o_beat = phase_q;
 
assign o_busy = (state_q != sys_pkg::ST_IDLE);
assign o_run_start = (state_q == sys_pkg::ST_CHECK) & ~bad_q;
assign o_done_set = (state_q == sys_pkg::ST_DONE);
assign o_err_set = ((state_q == sys_pkg::ST_CHECK) & bad_q) | (start_pulse & (state_q != sys_pkg::ST_IDLE));
assign o_state = state_q;
 
assign o_pp_en = pp_en_q;
assign o_relu_en = relu_q;
assign o_shift = shift_q;
assign o_round_const = round_const_q;
assign o_caddr = caddr_q;
assign o_count = count_q;

endmodule
`default_nettype wire
