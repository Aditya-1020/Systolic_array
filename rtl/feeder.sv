`default_nettype none
module feeder #(
    parameter int VW = 64,
    parameter int AW = 7,
    parameter int WROWS = 8
)(
    input wire i_clk,
    input wire i_rstn,

    input wire i_cmd_load_w,
    input wire i_cmd_start,
    input wire [AW:0] i_w_base,
    input wire [AW:0] i_a_base,
    input wire [AW:0] i_count,
    output logic o_cmd_ready,

    input wire [1:0] i_act_full,
    output logic o_act_clr,
    output logic o_act_clr_half,

    input wire [VW-1:0] i_r_data,
    input wire i_r_valid,
    output logic o_r_en,
    output logic [AW:0] o_r_addr,

    input wire i_w_tready,
    input wire i_a_tready,
    output logic o_w_tvalid,
    output logic o_a_tvalid,
    output logic o_a_tlast,
    output logic [VW-1:0] o_tdata
);
typedef enum logic [1:0] { S_IDLE, S_WAIT, S_ISSUE, S_DRAIN } state_t;
state_t state_q, next_state;
logic mode_w_q, half_q;
logic [AW:0] addr_q, left_q;
logic arr_last_q;

logic [1:0] cnt_q, cnt_next;
logic [VW-1:0] d0_q, d1_q, d0_next, d1_next;
logic l0_q, l1_q, l0_next, l1_next;

logic go_w, go_a, credit_ok, issue, issue_last;
logic fifo_ne, out_valid, out_ready, out_last;
logic pop_head, bypass, push;
logic [VW-1:0] out_data;
logic [2:0] occ;

assign o_cmd_ready = (state_q == S_IDLE);
assign go_w = o_cmd_ready && i_cmd_load_w;
assign go_a = o_cmd_ready && i_cmd_start && !i_cmd_load_w;

assign occ = {1'b0, cnt_q} + {2'b0, i_r_valid};
assign credit_ok = (occ <= 3'd1);
assign issue = (state_q == S_ISSUE) && credit_ok;
assign issue_last = issue && (left_q == (AW+1)'(1));


assign o_r_en = issue;
assign o_r_addr = addr_q;
assign o_act_clr = issue_last;
assign o_act_clr_half = half_q;

always_comb begin
    next_state = state_q;
    unique case (state_q)
        S_IDLE: if (go_w || go_a) next_state = S_WAIT;
        S_WAIT: if (i_act_full[half_q]) next_state = S_ISSUE;
        S_ISSUE: if (issue_last) next_state = S_DRAIN;
        S_DRAIN: if (cnt_q == 2'd0 && !i_r_valid) next_state = S_IDLE;
    endcase
end

always_ff @(posedge i_clk or negedge i_rstn) begin
    if (!i_rstn) begin
        state_q <= S_IDLE;
        mode_w_q <= '0;
        half_q <= '0;
        addr_q <= '0;
        left_q <= '0;
        arr_last_q <= '0;
    end else begin
        state_q <= next_state;
        arr_last_q <= issue_last;
        if (go_w) begin
            mode_w_q <= 1'b1;
            half_q <= i_w_base[AW];
            addr_q <= i_w_base + (AW+1)'(WROWS-1);
            left_q <= (AW+1)'(WROWS);
        end else if (go_a) begin
            mode_w_q <= 1'b0;
            half_q <= i_a_base[AW];
            addr_q <= i_a_base;
            left_q <= i_count;
        end else if (issue) begin
            addr_q <= mode_w_q ? (addr_q - 1'b1) : (addr_q + 1'b1);
            left_q <= left_q - 1'b1;
        end
    end
end

assign fifo_ne = (cnt_q != 2'd0);
assign out_valid = fifo_ne || i_r_valid;
assign out_data = fifo_ne ? d0_q : i_r_data;
assign out_last = fifo_ne ? l0_q : arr_last_q;
assign out_ready = mode_w_q ? i_w_tready : i_a_tready;
assign o_tdata = out_data;
assign o_w_tvalid = out_valid && mode_w_q;
assign o_a_tvalid = out_valid && !mode_w_q;
assign o_a_tlast = out_last;

assign pop_head = fifo_ne && out_ready;
assign bypass = !fifo_ne && i_r_valid && out_ready;
assign push = i_r_valid && !bypass;

always_comb begin
    cnt_next = cnt_q;
    d0_next = d0_q; l0_next = l0_q;
    d1_next = d1_q; l1_next = l1_q;
    if (pop_head) begin
        d0_next = d1_q; l0_next = l1_q;
        cnt_next = cnt_q - 2'd1;
    end
    if (push) begin
        if (cnt_next == 2'd0) begin
            d0_next = i_r_data;
            l0_next = arr_last_q;
        end else begin
            d1_next = i_r_data;
            l1_next = arr_last_q;
        end
        cnt_next = cnt_next + 2'd1;
    end
end

always_ff @(posedge i_clk or negedge i_rstn) begin
    if (!i_rstn) begin
        cnt_q <= 2'd0;
    end else begin
        cnt_q <= cnt_next;
    end
end

always_ff @(posedge i_clk) begin
    d0_q <= d0_next;
    l0_q <= l0_next;
    d1_q <= d1_next;
    l1_q <= l1_next;
end

endmodule
`default_nettype wire
