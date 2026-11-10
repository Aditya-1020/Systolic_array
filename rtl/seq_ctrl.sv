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
    output logic o_pp_en,
    output logic o_relu_en,
    output logic [SH_W-1:0] o_shift,
    output logic [ACC_W-1:0] o_round_const,
    output logic [sys_pkg::p_rbuf_aw-1:0] o_caddr,
    output logic [ROW_W-1:0] o_count,
    output logic o_wbuf_req,
    output logic [sys_pkg::p_wbuf_macro_aw-1:0] o_wbuf_addr,
    input wire i_wbuf_rvalid,

    output logic o_abuf_req,
    output logic [sys_pkg::p_abuf_aw-1:0] o_abuf_addr,
    input wire i_abuf_rvalid,
    input wire [sys_pkg::p_beat_w-1:0] i_abuf_rdata,

    output logic o_w_load,
    output logic o_a_advance,
    output logic o_a_valid,
    output logic [sys_pkg::p_beat_w-1:0] o_a_data,
    output logic [BEAT_W-1:0] o_beat,
    input wire i_c_valid,
    input wire i_all_written,

    output logic o_dp_active
);
localparam int WL_W = $clog2(N + 1);
localparam int WA_W = sys_pkg::p_wbuf_aw;
localparam int WMA_W = sys_pkg::p_wbuf_macro_aw;
localparam int AA_W = sys_pkg::p_abuf_aw;
localparam int RBEATS_W = ROW_W + $clog2(sys_pkg::p_raw_beats);
localparam int A_END_W = ((AA_W > ROW_W) ? AA_W : ROW_W) + 1;
localparam int C_END_W =
    ((sys_pkg::p_rbuf_aw > RBEATS_W) ? sys_pkg::p_rbuf_aw : RBEATS_W) + 1;
localparam int W_LEN_W = $clog2(N + 1);
localparam int W_END_W = ((WA_W > W_LEN_W) ? WA_W : W_LEN_W) + 1;

// split-adder geometry: A-end low=3b, C-end low=4b (clamped so high >= 1b)
localparam int A_LO_W = (A_END_W > 3) ? 3 : (A_END_W - 1);
localparam int A_HI_W = A_END_W - A_LO_W;
localparam int C_LO_W = (C_END_W > 4) ? 4 : (C_END_W - 1);
localparam int C_HI_W = C_END_W - C_LO_W;
localparam bit WL_LAST_IDLE = (N == 1);


logic st_idle_q, st_wload_q, st_run_q, st_flush_q, st_done_q;
logic running_q;
logic idle_d, wload_d, run_d, flush_d, done_d;
logic [3:0] chk_q;

logic [A_END_W-1:0] a_end_q;
logic [C_END_W-1:0] c_end_q;
logic [W_END_W-1:0] w_end_q;
logic [RBEATS_W-1:0] rbuf_beats_q;

logic a_cy_q, c_cy_q;
logic bad_count, bad_abuf, bad_rbuf, bad_wbuf, bad_shift, bad_cfg;
logic bad_pre_q;
logic chk_exit_bad, chk_exit_ok;
logic accept, start_q, start_pulse;

logic w_load_q, pp_en_q, relu_q, round_en_q;
logic [sys_pkg::p_wbuf_aw-1:0] waddr_q;
logic [sys_pkg::p_abuf_aw-1:0] aaddr_q;
logic [sys_pkg::p_rbuf_aw-1:0] caddr_q;
logic [ROW_W-1:0] count_q;
logic [SH_W-1:0] shift_q;
logic [ACC_W-1:0] round_const_q;
logic fire, adv_pre, adv_d, adv_q, hit_last;
logic abuf_req_d, abuf_req_q;
logic abuf_hold_q;
logic [sys_pkg::p_beat_w-1:0] abuf_data_q;
logic wl_last_q, rd_last;
logic [WL_W-1:0] wl_cnt_q;
logic [ROW_W-1:0] rd_rem_q, fire_rem_q;
logic rd_more_q, rd_one_q, fire_one_q;
logic [BEAT_W-1:0] phase_q;
logic phase_hit_q;
logic [sys_pkg::p_abuf_aw-1:0] abuf_addr_q;
logic [sys_pkg::p_wbuf_aw-1:0] wbuf_addr_q;
logic stop_adv_q;
logic wbuf_pend_q;
logic [1:0] run_pulse_q;
logic [ACC_W-1:0] round_const_d;

logic [A_END_W-1:0] aaddr_x, count_ax;
logic [C_END_W-1:0] caddr_x, rbeats_x;
logic [A_LO_W:0] a_lo_sum;
logic [A_HI_W-1:0] a_hi_sum;
logic [C_LO_W:0] c_lo_sum;
logic [C_HI_W-1:0] c_hi_sum;



assign aaddr_x  = A_END_W'(aaddr_q);
assign count_ax = A_END_W'(count_q);
assign caddr_x  = C_END_W'(caddr_q);
assign rbeats_x = C_END_W'(rbuf_beats_q);

fast_add #(.W(A_LO_W)) u_a_lo (
    .a(aaddr_x[A_LO_W-1:0]), .b(count_ax[A_LO_W-1:0]), .cin(1'b0),
    .sum(a_lo_sum[A_LO_W-1:0]), .cout(a_lo_sum[A_LO_W]));
fast_add_cs #(.W(A_HI_W), .GROUP_W(2)) u_a_hi (
    .a(aaddr_x[A_END_W-1:A_LO_W]),
    .b(count_ax[A_END_W-1:A_LO_W]),
    .cin(a_cy_q),
    .sum(a_hi_sum),
    .cout()
);
fast_add #(.W(C_LO_W)) u_c_lo (
    .a(caddr_x[C_LO_W-1:0]), .b(rbeats_x[C_LO_W-1:0]), .cin(1'b0),
    .sum(c_lo_sum[C_LO_W-1:0]), .cout(c_lo_sum[C_LO_W]));
fast_add_cs #(.W(C_HI_W), .GROUP_W(2)) u_c_hi (
    .a(caddr_x[C_END_W-1:C_LO_W]),
    .b(rbeats_x[C_END_W-1:C_LO_W]),
    .cin(c_cy_q),
    .sum(c_hi_sum),
    .cout()
);

always_comb begin
    round_const_d = '0;
    for (int i = 0; i < ACC_W; i++) begin
        round_const_d[i] = round_en_q && (shift_q == SH_W'(i+1));
    end
end

assign start_pulse = i_start & ~start_q;
assign accept = start_pulse & st_idle_q;

always_ff @(posedge i_clk) begin
    if (!i_rstn)
        start_q <= 1'b0;
    else
        start_q <= i_start;
end

assign bad_count = (count_q == '0) | (count_q > ROW_W'(sys_pkg::p_max_rows));
assign bad_abuf  = (a_end_q > A_END_W'(sys_pkg::p_abuf_depth));
assign bad_rbuf  = (c_end_q > C_END_W'(sys_pkg::p_rbuf_depth));
assign bad_wbuf  = w_load_q & (w_end_q > W_END_W'(sys_pkg::p_wbuf_depth));
assign bad_shift = pp_en_q & (shift_q > SH_W'(sys_pkg::p_shift_max));
assign bad_cfg = bad_pre_q | bad_rbuf;

// Config / flag regs (reset)
always_ff @(posedge i_clk) begin
    if (!i_rstn) begin
        bad_pre_q <= 1'b0;
        w_load_q <= 1'b0;
        pp_en_q <= 1'b1;
        relu_q <= 1'b0;
        round_en_q <= 1'b0;
        waddr_q <= '0;
        aaddr_q <= '0;
        caddr_q <= '0;
        count_q <= '0;
        shift_q <= '0;
        round_const_q <= '0;
    end else if (accept) begin
        w_load_q <= i_w_load_en;
        pp_en_q <= i_pp_en;
        relu_q <= i_relu_en;
        round_en_q <= i_round_en;
        waddr_q <= i_waddr[sys_pkg::p_wbuf_aw-1:0];
        aaddr_q <= i_aaddr[sys_pkg::p_abuf_aw-1:0];
        caddr_q <= i_caddr[sys_pkg::p_rbuf_aw-1:0];
        count_q <= i_count[ROW_W-1:0];
        shift_q <= i_shift;
    end else if (chk_q[0]) begin
        bad_pre_q <= bad_count | bad_shift;
    end else if (chk_q[1]) begin
        round_const_q <= round_const_d;
        bad_pre_q <= bad_pre_q | bad_wbuf;
    end else if (chk_q[2]) begin
        bad_pre_q <= bad_pre_q | bad_abuf;
    end
end

always_ff @(posedge i_clk) begin
    if (chk_q[0]) begin
        rbuf_beats_q <= pp_en_q
            ? RBEATS_W'(count_q)
            : (RBEATS_W'(count_q) << $clog2(sys_pkg::p_raw_beats));
        a_end_q[A_LO_W-1:0] <= a_lo_sum[A_LO_W-1:0];
        a_cy_q <= a_lo_sum[A_LO_W];
        w_end_q <= W_END_W'(waddr_q) + W_END_W'(N);
    end
    if (chk_q[1]) begin
        a_end_q[A_END_W-1:A_LO_W] <= a_hi_sum;
        c_end_q[C_LO_W-1:0] <= c_lo_sum[C_LO_W-1:0];
        c_cy_q <= c_lo_sum[C_LO_W];
    end
    if (chk_q[2])
        c_end_q[C_END_W-1:C_LO_W] <= c_hi_sum;
end

assign chk_exit_bad = chk_q[3] & bad_cfg;
assign chk_exit_ok = chk_q[3] & ~bad_cfg;

assign idle_d = (st_idle_q & ~start_pulse) | chk_exit_bad | st_done_q;
assign wload_d = (chk_exit_ok & w_load_q) | (st_wload_q & ~wl_last_q);
assign run_d = (chk_exit_ok & ~w_load_q) | (st_wload_q & wl_last_q) | (st_run_q & ~rd_last);
assign flush_d = (st_run_q & rd_last) | (st_flush_q & ~i_all_written);
assign done_d = st_flush_q & i_all_written;

assign fire = adv_q & i_c_valid;
assign hit_last = fire & fire_one_q;
assign adv_pre = running_q & ~stop_adv_q & (pp_en_q | phase_hit_q);
assign adv_d = adv_pre & ~hit_last;
assign abuf_req_d = adv_pre & rd_more_q & ~hit_last;
assign rd_last = abuf_req_q & rd_one_q;
assign o_wbuf_req = st_wload_q;

always_ff @(posedge i_clk) begin
    if (!i_rstn) begin
        st_idle_q <= 1'b1;
        st_wload_q <= 1'b0;
        st_run_q <= 1'b0;
        st_flush_q <= 1'b0;
        st_done_q <= 1'b0;
        running_q <= 1'b0;
        chk_q <= '0;
        adv_q <= 1'b0;
        abuf_req_q <= 1'b0;
        wl_cnt_q <= '0;
        wl_last_q <= WL_LAST_IDLE;
        rd_rem_q <= '0;
        rd_more_q <= 1'b0;
        rd_one_q <= 1'b0;
        fire_rem_q <= '0;
        fire_one_q <= 1'b0;
        phase_q <= BEAT_W'(sys_pkg::p_raw_beats - 2);
        phase_hit_q <= 1'b1;
        abuf_addr_q <= '0;
        wbuf_addr_q <= '0;
        stop_adv_q <= 1'b0;
        wbuf_pend_q <= 1'b0;
        run_pulse_q <= '0;
        abuf_hold_q <= 1'b0;
        abuf_data_q <= '0;
    end else begin
        st_idle_q <= idle_d;
        st_wload_q <= wload_d;
        st_run_q <= run_d;
        st_flush_q <= flush_d;
        st_done_q <= done_d;
        running_q <= run_d | flush_d;
        chk_q <= {chk_q[2:0], accept};
        adv_q <= adv_d;
        abuf_req_q <= abuf_req_d;
        wbuf_pend_q <= st_wload_q;

        if (chk_exit_ok)
            run_pulse_q <= 2'b11;
        else
            run_pulse_q <= {1'b0, run_pulse_q[1]};

        if (st_wload_q) begin
            wl_cnt_q <= wl_cnt_q + 1'b1;
            wl_last_q <= (wl_cnt_q == WL_W'(N - 2));
            wbuf_addr_q <= wbuf_addr_q + 1'b1;
        end else begin
            wl_cnt_q <= '0;
            wl_last_q <= WL_LAST_IDLE;
            wbuf_addr_q <= waddr_q;
        end

        if (running_q) begin
            if (abuf_req_q) begin
                abuf_addr_q <= abuf_addr_q + 1'b1;
                if (rd_more_q) begin
                    rd_rem_q <= rd_rem_q - 1'b1;
                end
            end
            rd_more_q <= abuf_req_q ? (rd_rem_q > ROW_W'(1))  : (rd_rem_q != '0);
            rd_one_q <= abuf_req_q ? (rd_rem_q == ROW_W'(2)) : (rd_rem_q == ROW_W'(1));

            if (fire) begin
                fire_rem_q <= fire_rem_q - 1'b1;
            end
            fire_one_q <= fire ? (fire_rem_q == ROW_W'(2)) : (fire_rem_q == ROW_W'(1));

            phase_q <= phase_q + 1'b1;
            phase_hit_q <= ((phase_q + BEAT_W'(1)) == BEAT_W'(sys_pkg::p_raw_beats - 2));
            
            if (hit_last) begin
                stop_adv_q <= 1'b1;
            end

            if (i_abuf_rvalid) begin
                abuf_hold_q <= 1'b1;
                abuf_data_q <= i_abuf_rdata;
            end else if (adv_q) begin
                abuf_hold_q <= 1'b0;
                abuf_data_q <= '0;
            end
        end else begin
            rd_rem_q <= count_q;
            rd_more_q <= (count_q != '0);
            rd_one_q <= (count_q == ROW_W'(1));
            fire_rem_q <= count_q;
            fire_one_q <= (count_q == ROW_W'(1));
            abuf_addr_q <= aaddr_q;
            phase_q <= BEAT_W'(sys_pkg::p_raw_beats - 2);
            phase_hit_q <= 1'b1;
            stop_adv_q <= 1'b0;
            abuf_hold_q <= 1'b0;
            abuf_data_q <= '0;
        end
    end
end

assign o_wbuf_addr = WMA_W'(wbuf_addr_q);
assign o_abuf_addr = abuf_addr_q;
assign o_abuf_req = abuf_req_q;

assign o_w_load = wbuf_pend_q & i_wbuf_rvalid;
assign o_a_advance = adv_q;
assign o_a_valid = abuf_hold_q;
assign o_a_data = abuf_data_q;
assign o_beat = phase_q;

assign o_busy = ~st_idle_q;
assign o_run_start = run_pulse_q[0];
assign o_done_set = st_done_q;
assign o_err_set = chk_exit_bad | (start_pulse & ~st_idle_q);
assign o_dp_active = st_run_q | st_flush_q;

assign o_pp_en = pp_en_q;
assign o_relu_en = relu_q;
assign o_shift = shift_q;
assign o_round_const = round_const_q;
assign o_caddr = caddr_q;
assign o_count = count_q;

endmodule
`default_nettype wire
