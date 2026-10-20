`default_nettype none
module systolic_top #(
    parameter int N = 8,
    parameter int DW = 8,
    parameter int OW = 32, // core lane wiedth
    parameter int HALF_DEPTH = 128, // match macro
    parameter int VW = N*DW,
    parameter int AW = $clog2(HALF_DEPTH)
)(
    input wire i_clk,
    input wire i_rstn,
    
    input wire i_host_w_en,
    input wire [AW:0] i_host_w_addr,
    input wire [VW-1:0] i_host_w_data,
    input wire i_act_push,
    input wire i_act_push_half,

    input wire i_host_r_en,
    input wire [AW:0] i_host_r_addr,
    output logic [VW-1:0] o_host_r_data,
    output logic o_host_r_valid,
    input wire i_res_pop,
    input wire i_res_pop_half,

    input wire i_cmd_load_w,
    input wire i_cmd_start,
    input wire [AW:0] i_w_base,
    input wire [AW:0] i_a_base,
    input wire [AW:0] i_count,

    input wire [4:0] i_shift,
    input wire i_relu_en,
    input wire [N*OW-1:0] i_bias, // n * signed out

    output logic o_cmd_ready,
    output logic o_weights_loaded,
    output logic o_busy,
    output logic [1:0] o_act_full,
    output logic [1:0] o_res_full,
    output logic o_frame_done
);

wire rstn_sync;
reset_sync u_reset_sync ( .clk(i_clk), .arstn(i_rstn), .rstn_sync(rstn_sync));

logic [1:0] act_full_q, res_full_q;
logic feed_clear, feed_clear_half;
logic wr_set, wr_set_half, frame_done_q;

always_ff @(posedge i_clk or negedge rstn_sync) begin
    if (!rstn_sync) begin
        act_full_q <= '0;
        res_full_q <= '0;
        frame_done_q <= '0;
    end else begin
        frame_done_q <= wr_set;
        for (int h=0; h<2; h=h+1) begin
            if (i_act_push && (i_act_push_half == 1'(h))) begin
                act_full_q[h] <= 1'b1;
            end else if (feed_clear && (feed_clear_half == 1'(h))) begin
                act_full_q[h] <= 1'b0;
            end
            if (wr_set && (wr_set_half == 1'(h))) begin
                res_full_q[h] <= 1'b1;
            end else if (i_res_pop && (i_res_pop_half == 1'(h))) begin
                res_full_q[h] <= 1'b0;
            end
        end
    end
end

assign o_act_full = act_full_q;
assign o_res_full = res_full_q;
assign o_frame_done = frame_done_q;

logic a_r_en, a_r_valid;
logic [AW:0] a_r_addr;
logic [VW-1:0] a_r_data;

logic r_w_en;
logic [AW:0] r_w_addr;
logic [VW-1:0] r_w_data;

// inst ping pong result buffer sram
pp_buf_1r1w #(.DW(VW), .HALF_DEPTH(HALF_DEPTH), .AW(AW)) inst_acc_buf (
    .i_clk    (i_clk),
    .i_rstn   (rstn_sync),
    .i_w_en   (i_host_w_en),
    .i_w_addr (i_host_w_addr),
    .i_w_data (i_host_w_data),
    .i_r_en   (a_r_en),
    .i_r_addr (a_r_addr),
    .o_r_data (a_r_data),
    .o_r_valid(a_r_valid)
);

pp_buf_1r1w #(.DW(VW), .HALF_DEPTH(HALF_DEPTH), .AW(AW)) inst_res_buf (
    .i_clk    (i_clk),
    .i_rstn   (rstn_sync),
    .i_w_en   (r_w_en),
    .i_w_addr (r_w_addr),
    .i_w_data (r_w_data),
    .i_r_en   (i_host_r_en),
    .i_r_addr (i_host_r_addr),
    .o_r_data (o_host_r_data),
    .o_r_valid(o_host_r_valid)
);

/// feeder to core
logic f_w_tvalid, f_w_tready;
logic f_a_tvalid, f_a_tready, f_a_tlast;
logic [VW-1:0] f_tdata;

//feeeder inst
feeder #(.VW(VW), .AW(AW),.WROWS(N)) u_feeder (
    .i_clk          (i_clk),
    .i_rstn         (rstn_sync),
    .i_cmd_load_w   (i_cmd_load_w),
    .i_cmd_start    (i_cmd_start),
    .i_w_base       (i_w_base),
    .i_a_base       (i_a_base),
    .i_count        (i_count),
    .o_cmd_ready    (o_cmd_ready),
    .i_act_full     (act_full_q),
    .o_act_clr      (feed_clear),
    .o_act_clr_half (feed_clear_half),
    .o_r_en         (a_r_en),
    .o_r_addr       (a_r_addr),
    .i_r_data       (a_r_data),
    .i_r_valid      (a_r_valid),
    .o_w_tvalid     (f_w_tvalid),
    .i_w_tready     (f_w_tready),
    .o_a_tvalid     (f_a_tvalid),
    .i_a_tready     (f_a_tready),
    .o_a_tlast      (f_a_tlast),
    .o_tdata        (f_tdata)
);

logic c_tvalid, c_tready, c_tlast;
logic [N*OW-1:0] c_tdata;
logic core_busy;

systolic_array #(.N(N), .DW(DW), .OUT_W (OW)) u_core (
    .i_clk           (i_clk),
    .i_rstn          (rstn_sync),
    .i_load_w        (i_cmd_load_w && o_cmd_ready),
    .o_busy          (core_busy),
    .o_done          (),
    .o_weights_loaded(o_weights_loaded),
    .s_axis_w_tvalid (f_w_tvalid),
    .s_axis_w_tdata  (f_tdata),
    .s_axis_w_tready (f_w_tready),
    .s_axis_a_tvalid (f_a_tvalid),
    .s_axis_a_tdata  (f_tdata),
    .s_axis_a_tlast  (f_a_tlast),
    .s_axis_a_tready (f_a_tready),
    .m_axis_c_tready (c_tready),
    .m_axis_c_tvalid (c_tvalid),
    .m_axis_c_tdata  (c_tdata),
    .m_axis_c_tlast  (c_tlast)
);

logic pp_tvalid, pp_tready, pp_tlast;
logic [VW-1:0] pp_tdata;

// post proc int
postproc #(.N(N), .IW(OW), .DW(DW)) u_postproc (
    .i_clk       (i_clk),
    .i_rstn      (rstn_sync),
    .i_shift     (i_shift),
    .i_relu_en   (i_relu_en),
    .i_bias      (i_bias),
    .i_s_tvalid  (c_tvalid),
    .o_s_tready  (c_tready),
    .i_s_tdata   (c_tdata),
    .i_s_tlast   (c_tlast),
    .o_m_tvalid  (pp_tvalid),
    .i_m_tready  (pp_tready),
    .o_m_tdata   (pp_tdata),
    .o_m_tlast   (pp_tlast)
);

result_writer #(.VW(VW), .AW(AW)) u_writer (
    .i_clk       (i_clk),
    .i_rstn      (rstn_sync),
    .i_s_tvalid  (pp_tvalid),
    .o_s_tready  (pp_tready),
    .i_s_tdata   (pp_tdata),
    .i_s_tlast   (pp_tlast),
    .i_res_full  (res_full_q),
    .o_set_full  (wr_set),
    .o_set_half  (wr_set_half),
    .o_w_en      (r_w_en),
    .o_w_addr    (r_w_addr),
    .o_w_data    (r_w_data)
);

assign o_busy = !o_cmd_ready || core_busy || pp_tvalid;

`ifndef SYNTHESIS
    always @(posedge i_clk) begin
        if (rstn_sync) begin
            if (i_host_w_en && act_full_q[i_host_w_addr[AW]]) begin
                $error("sys mem: host wrote act half when full");
            end
            if (i_host_r_en && !res_full_q[i_host_r_addr[AW]]) begin
                $error("sys mem: host read result half not full");
            end
            if (i_act_push && act_full_q[i_act_push_half]) begin
                $error("sys mem: act push to half already full");
            end
            if (i_res_pop && !res_full_q[i_res_pop_half]) begin
                $error("sys mem: res pop of half not full");
            end
            if ((i_cmd_load_w || i_cmd_start) && !o_cmd_ready) begin
                $warning("sy_mem: command ignored feeder busy");
            end
        end
    end
`endif

endmodule
`default_nettype wire
