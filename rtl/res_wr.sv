`default_nettype none
module res_wr #(
    parameter int N = sys_pkg::p_n,
    parameter int DW = sys_pkg::p_dw,
    parameter int ACC_W = sys_pkg::p_acc_w,
    parameter int ROW_W = $clog2(sys_pkg::p_max_rows + 1),
    parameter int BEAT_W = $clog2(sys_pkg::p_raw_beats)
) (
    input wire i_clk,
    input wire i_rstn,
    input wire i_run_start,
    input sys_pkg::output_mode_t i_mode,
    input wire [sys_pkg::p_rbuf_aw-1:0] i_caddr,
    input wire [ROW_W-1:0] i_count,
    input wire i_pp_valid,
    input wire [N*DW-1:0] i_pp_data,
    input wire i_raw_valid,
    input wire [N*ACC_W-1:0] i_raw_data,
    output logic o_rbuf_req,
    output logic [sys_pkg::p_rbuf_aw-1:0] o_rbuf_addr,
    output logic [sys_pkg::p_beat_w-1:0] o_rbuf_wdata,
    output logic [sys_pkg::p_beat_w-1:0] o_rbuf_wmask,
    output logic o_all_written
);
localparam int RA_W = sys_pkg::p_rbuf_aw;
localparam int COLS_PER_BEAT = sys_pkg::p_beat_w / sys_pkg::p_raw_col_w;
localparam int STRIDE_LOG2 = $clog2(sys_pkg::p_raw_beats);

logic raw_wr, pp_wr, raw_mode, row_done, raw_last;
logic raw_active_q;
logic [BEAT_W-1:0] raw_beat_q;
logic [sys_pkg::p_raw_beats-1:0] raw_beat_oh_q;
logic [N*ACC_W-1:0] raw_data_q;
logic [ROW_W-1:0] rows_q, count_q;
logic [RA_W-1:0] beat_off;
logic [RA_W-1:0] row_addr_q;
logic [RA_W-1:0] row_addr_inc1_toggle;
logic [RA_W-1:0] row_addr_inc_raw_toggle;
logic [RA_W-1:0] row_addr_toggle;
logic raw_mode_q;
logic [sys_pkg::p_raw_beats-1:0][sys_pkg::p_beat_w-1:0] raw_beat_data;
logic [sys_pkg::p_beat_w-1:0] raw_beat_sel_data;
logic [ROW_W-1:0] rows_toggle;

genvar b, c;
generate
    for (b = 0; b < sys_pkg::p_raw_beats; b++) begin : g_beat
        for (c = 0; c < COLS_PER_BEAT; c++) begin : g_col
            localparam int COL = b*COLS_PER_BEAT + c;
            assign raw_beat_data[b][c*sys_pkg::p_raw_col_w +: sys_pkg::p_raw_col_w] =
                {{(sys_pkg::p_raw_col_w - ACC_W){raw_data_q[COL*ACC_W + ACC_W-1]}}, raw_data_q[COL*ACC_W +: ACC_W]};
        end
    end
endgenerate

assign raw_mode = (i_mode == sys_pkg::MODE_RAW);
assign raw_wr = raw_mode_q & raw_active_q;
assign pp_wr = ~raw_mode_q & i_pp_valid;
assign raw_last = raw_beat_oh_q[sys_pkg::p_raw_beats-1];
assign row_done = pp_wr | (raw_wr & raw_last);

always_comb begin
    raw_beat_sel_data = '0;
    for (int bsel = 0; bsel < sys_pkg::p_raw_beats; bsel++) begin
        raw_beat_sel_data |= raw_beat_data[bsel] & {sys_pkg::p_beat_w{raw_beat_oh_q[bsel]}};
    end
end

assign rows_toggle[0] = row_done;
generate
    for (genvar ri = 1; ri < ROW_W; ri++) begin : g_rows_toggle
        assign rows_toggle[ri] = row_done & (&rows_q[ri-1:0]);
    end
endgenerate

assign beat_off = raw_mode_q ? RA_W'(raw_beat_q) : '0;
assign row_addr_inc1_toggle[0] = 1'b1;

generate
    for (genvar r1 = 1; r1 < RA_W; r1++) begin : g_row_addr_inc1
        assign row_addr_inc1_toggle[r1] = &row_addr_q[r1-1:0];
    end
endgenerate

generate
    if (STRIDE_LOG2 < RA_W) begin : g_row_addr_inc_raw
        for (genvar r0 = 0; r0 < STRIDE_LOG2; r0++) begin : g_low
            assign row_addr_inc_raw_toggle[r0] = 1'b0;
        end
        assign row_addr_inc_raw_toggle[STRIDE_LOG2] = 1'b1;
        for (genvar r2 = STRIDE_LOG2 + 1; r2 < RA_W; r2++) begin : g_high
            assign row_addr_inc_raw_toggle[r2] =
                &row_addr_q[r2-1:STRIDE_LOG2];
        end
    end else begin : g_row_addr_inc_raw_wrap
        assign row_addr_inc_raw_toggle = '0;
    end
endgenerate

assign row_addr_toggle = raw_mode_q ? row_addr_inc_raw_toggle : row_addr_inc1_toggle;

logic req_d, req_q;
logic [RA_W-1:0] base_q, addr_q;
logic [sys_pkg::p_beat_w-1:0] wdata_d, wdata_q;
logic [RA_W-1:0] beat_off_d;

assign o_rbuf_req = req_q;
assign o_rbuf_addr = addr_q;
assign o_rbuf_wdata = wdata_q;
assign o_rbuf_wmask = '1;

always_ff @(posedge i_clk) begin
    if (!i_rstn) begin
        rows_q <= '0;
        row_addr_q <= '0;
        raw_active_q <= 1'b0;
        raw_beat_q <= '0;
        raw_beat_oh_q <= {{(sys_pkg::p_raw_beats-1){1'b0}}, 1'b1};
        raw_mode_q <= 1'b0;
        count_q <= '0;
        req_d <= 1'b0;
        req_q <= 1'b0;
        base_q <= '0;
        addr_q <= '0;
        wdata_d <= '0;
        wdata_q <= '0;
        beat_off_d <= '0;
    end else if (i_run_start) begin
        rows_q <= '0;
        row_addr_q <= i_caddr;
        raw_active_q <= 1'b0;
        raw_beat_q <= '0;
        raw_beat_oh_q <= {{(sys_pkg::p_raw_beats-1){1'b0}}, 1'b1};
        raw_mode_q <= raw_mode;
        count_q <= i_count;
        req_d <= 1'b0;
        req_q <= 1'b0;
        base_q <= '0;
        addr_q <= '0;
        wdata_d <= '0;
        wdata_q <= '0;
        beat_off_d <= '0;
    end else begin
        rows_q <= rows_q ^ rows_toggle;
        row_addr_q <= row_addr_q ^ (row_addr_toggle & {RA_W{row_done}});

        if (raw_mode_q) begin
            if (raw_active_q) begin
                if (raw_last) begin
                    raw_beat_q <= '0;
                    raw_beat_oh_q <= {{(sys_pkg::p_raw_beats-1){1'b0}}, 1'b1};
                    if (!i_raw_valid)
                        raw_active_q <= 1'b0;
                end else begin
                    raw_beat_q <= raw_beat_q + 1'b1;
                    raw_beat_oh_q <= (raw_beat_oh_q << 1) | {{(sys_pkg::p_raw_beats-1){1'b0}}, raw_beat_oh_q[sys_pkg::p_raw_beats-1]};
                end
            end else if (i_raw_valid) begin
                raw_active_q <= 1'b1;
                raw_beat_q <= '0;
                raw_beat_oh_q <= {{(sys_pkg::p_raw_beats-1){1'b0}}, 1'b1};
            end
        end else begin
            raw_active_q <= 1'b0;
            raw_beat_q <= '0;
            raw_beat_oh_q <= {{(sys_pkg::p_raw_beats-1){1'b0}}, 1'b1};
        end

        req_d <= raw_wr | pp_wr;
        base_q <= row_addr_q;
        beat_off_d <= beat_off;
        wdata_d <= raw_mode_q ? raw_beat_sel_data : i_pp_data;

        req_q <= req_d;
        addr_q <= base_q + beat_off_d;
        wdata_q <= wdata_d;
    end
end

logic raw_data_clk;
OPENROAD_CLKGATE u_cg_raw_data (.CK(i_clk), .E(i_raw_valid), .GCK(raw_data_clk));

always_ff @(posedge raw_data_clk) begin
    raw_data_q <= i_raw_data;
end

assign o_all_written = (rows_q == count_q);

endmodule
`default_nettype wire
