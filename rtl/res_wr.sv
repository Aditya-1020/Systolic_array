//result writer 
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

logic raw_wr, pp_wr, raw_mode, row_done, raw_last;
// RAW results are captured once, then written as consecutive 64-bit beats.
logic raw_active_q;
logic [BEAT_W-1:0] raw_beat_q;
logic [N*ACC_W-1:0] raw_data_q;
logic [ROW_W-1:0] rows_q;
logic [sys_pkg::p_rbuf_aw-1:0] row_base, beat_off;
logic [sys_pkg::p_raw_beats-1:0][sys_pkg::p_beat_w-1:0] raw_beat_data;

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
assign raw_wr = raw_mode & raw_active_q;
assign pp_wr = ~raw_mode & i_pp_valid;
assign raw_last = (raw_beat_q == BEAT_W'(sys_pkg::p_raw_beats - 1));
assign row_done = pp_wr | (raw_wr & raw_last);
 
assign row_base = raw_mode ? RA_W'(rows_q * sys_pkg::p_raw_beats) : RA_W'(rows_q);
assign beat_off = raw_mode ? RA_W'(raw_beat_q) : '0;
 
assign o_rbuf_req = raw_wr | pp_wr;
assign o_rbuf_addr = i_caddr + row_base + beat_off;
assign o_rbuf_wdata = raw_mode ? raw_beat_data[raw_beat_q] : i_pp_data;
assign o_rbuf_wmask = '1;

always_ff @(posedge i_clk) begin
    if (!i_rstn) begin
        rows_q <= '0;
        raw_active_q <= 1'b0;
        raw_beat_q <= '0;
    end else if (i_run_start) begin
        rows_q <= '0;
        raw_active_q <= 1'b0;
        raw_beat_q <= '0;
    end else begin
        if (row_done)
            rows_q <= rows_q + 1'b1;

        if (raw_mode) begin
            if (i_raw_valid) begin
                raw_active_q <= 1'b1;
                raw_beat_q <= '0;
            end else if (raw_active_q) begin
                if (raw_last) begin
                    raw_active_q <= 1'b0;
                    raw_beat_q <= '0;
                end else begin
                    raw_beat_q <= raw_beat_q + 1'b1;
                end
            end
        end else begin
            raw_active_q <= 1'b0;
            raw_beat_q <= '0;
        end
    end
end

logic raw_data_clk;
OPENROAD_CLKGATE u_cg_raw_data (.CK(i_clk), .E(i_raw_valid), .GCK(raw_data_clk));

always_ff @(posedge raw_data_clk) begin
    raw_data_q <= i_raw_data;
end

assign o_all_written = (rows_q == i_count);

endmodule
`default_nettype wire
