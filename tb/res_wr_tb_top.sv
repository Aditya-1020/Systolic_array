// Unit-test wrapper for the result writer.
`default_nettype none
module res_wr_tb_top (
    input logic i_clk,
    input logic i_rstn,
    input logic i_run_start,
    input sys_pkg::output_mode_t i_mode,
    input logic [sys_pkg::p_rbuf_aw-1:0] i_caddr,
    input logic [$clog2(sys_pkg::p_max_rows+1)-1:0] i_count,
    input logic i_pp_valid,
    input logic [sys_pkg::p_n*sys_pkg::p_dw-1:0] i_pp_data,
    input logic i_raw_valid,
    input logic [sys_pkg::p_n*sys_pkg::p_acc_w-1:0] i_raw_data,
    output logic o_rbuf_req,
    output logic [sys_pkg::p_rbuf_aw-1:0] o_rbuf_addr,
    output logic [sys_pkg::p_beat_w-1:0] o_rbuf_wdata,
    output logic [sys_pkg::p_beat_w-1:0] o_rbuf_wmask,
    output logic o_all_written
);
    res_wr u_dut (
        .i_clk,
        .i_rstn,
        .i_run_start,
        .i_mode,
        .i_caddr,
        .i_count,
        .i_pp_valid,
        .i_pp_data,
        .i_raw_valid,
        .i_raw_data,
        .o_rbuf_req,
        .o_rbuf_addr,
        .o_rbuf_wdata,
        .o_rbuf_wmask,
        .o_all_written
    );
endmodule
`default_nettype wire
