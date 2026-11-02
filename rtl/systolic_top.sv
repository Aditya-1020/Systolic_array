`default_nettype none
module systolic_top #(
    parameter int N = 8,
    parameter int DW = 8,
    parameter int OUT_W = 32,
    parameter int Q_W = 8,
    parameter int MULT_W = 16,
    parameter int BIAS_W = 16,
    parameter int MEM_DW = N*DW,
    parameter int W_DEPTH = 256,
    parameter int A_DEPTH = 256,
    parameter int R_DEPTH = 512,
    parameter int W_AW = $clog2(W_DEPTH),
    parameter int A_AW = $clog2(A_DEPTH),
    parameter int R_AW = $clog2(R_DEPTH),
    parameter int ACC_W = 2*DW + ((N > 1) ? $clog2(N) : 1),
    parameter int SHIFT_W = $clog2(ACC_W + MULT_W + 1),
    parameter int CSR_AW = 6 // must match the generated s_apb_paddr width (map ends at 0x24 -> 6 bits)
)(
    input wire i_clk,
    input wire i_rstn,

    input wire s_apb_psel,
    input wire s_apb_penable,
    input wire s_apb_pwrite,
    input logic [2:0] s_apb_pprot,
    input logic [CSR_AW-1:0] s_apb_paddr,
    input logic [31:0] s_apb_pwdata,
    input logic [3:0] s_apb_pstrb,
    output logic s_apb_pready,
    output logic [31:0] s_apb_prdata,
    output logic s_apb_pslverr,

    output logic o_irq,
    output logic o_busy,

    output logic o_w_ce,
    output logic [W_AW-1:0] o_w_addr,
    input logic [MEM_DW-1:0] i_w_rdata,

    output logic o_a_ce,
    output logic [A_AW-1:0] o_a_addr,
    input logic [MEM_DW-1:0] i_a_rdata,

    output logic o_r_ce,
    output logic [R_AW-1:0] o_r_addr,
    output logic [MEM_DW-1:0] o_r_wdata
);

import sysarray_csr_pkg::*;
sysarray_csr__in_t csr_in;
sysarray_csr__out_t csr_out;

logic csr_rst;
logic busy, w_valid, done, start_acc, err_cmd, err_cfg;
logic bias_shift, w_shift, a_vld, a_last, flush;
logic c_vld, c_last;
logic [N*OUT_W-1:0] c_data;

assign o_busy = busy;
assign csr_rst = !i_rstn;

always_comb begin
    csr_in = '{default: '0};
    csr_in.STATUS.BUSY.next = busy;
    csr_in.STATUS.W_VALID.next = w_valid;
    csr_in.STATUS.DONE.hwset = done;
    csr_in.STATUS.DONE.hwclr = start_acc;
    csr_in.STATUS.CMD_ERR.hwset = err_cmd;
    csr_in.STATUS.CFG_ERR.hwset = err_cfg;
    csr_in.cfg_lock = busy;
end

assign o_irq = (csr_out.STATUS.DONE.value && csr_out.INT_ENABLE.DONE_IE.value) ||
               ((csr_out.STATUS.CMD_ERR.value || csr_out.STATUS.CFG_ERR.value) &&
                csr_out.INT_ENABLE.ERR_IE.value);

sysarray_csr u_csr (
    .clk          (i_clk),
    .rst          (csr_rst),
    .s_apb_psel   (s_apb_psel),
    .s_apb_penable(s_apb_penable),
    .s_apb_pwrite (s_apb_pwrite),
    .s_apb_pprot  (s_apb_pprot),
    .s_apb_paddr  (s_apb_paddr),
    .s_apb_pwdata (s_apb_pwdata),
    .s_apb_pstrb  (s_apb_pstrb),
    .s_apb_pready (s_apb_pready),
    .s_apb_prdata (s_apb_prdata),
    .s_apb_pslverr(s_apb_pslverr),
    .hwif_in      (csr_in),
    .hwif_out     (csr_out)
);

systolic_ctrl #(
    .N(N), .OUT_W(OUT_W), .Q_W(Q_W), .BIAS_W(BIAS_W), .MEM_DW(MEM_DW),
    .W_DEPTH(W_DEPTH), .A_DEPTH(A_DEPTH), .R_DEPTH(R_DEPTH)
) u_ctrl (
    .i_clk       (i_clk),
    .i_rstn      (i_rstn),
    .i_load_w    (csr_out.COMMAND.LOAD_W.value),
    .i_start     (csr_out.COMMAND.START.value),
    .i_abort     (csr_out.COMMAND.ABORT.value),
    .i_quant_en  (csr_out.POSTPROC_CFG.REQUANT_EN.value),
    .i_w_addr    (csr_out.WEIGHT_ADDR.ADDR.value),
    .i_a_addr    (csr_out.ACT_ADDR.ADDR.value),
    .i_a_count   (csr_out.ACT_COUNT.COUNT.value),
    .i_r_addr    (csr_out.DST_ADDR.ADDR.value),
    .o_busy      (busy),
    .o_w_valid   (w_valid),
    .o_done      (done),
    .o_start_acc (start_acc),
    .o_err_cmd   (err_cmd),
    .o_err_cfg   (err_cfg),
    .o_w_ce      (o_w_ce),
    .o_w_addr    (o_w_addr),
    .o_a_ce      (o_a_ce),
    .o_a_addr    (o_a_addr),
    .o_r_ce      (o_r_ce),
    .o_r_addr    (o_r_addr),
    .o_r_wdata   (o_r_wdata),
    .o_bias_shift(bias_shift),
    .o_w_shift   (w_shift),
    .o_a_vld     (a_vld),
    .o_a_last    (a_last),
    .o_flush     (flush),
    .i_c_vld     (c_vld),
    .i_c_last    (c_last),
    .i_c_data    (c_data)
);

systolic_core #(
    .N(N), .DW(DW), .OUT_W(OUT_W), .Q_W(Q_W), .MULT_W(MULT_W), .BIAS_W(BIAS_W),
    .MEM_DW(MEM_DW), .ACC_W(ACC_W), .SHIFT_W(SHIFT_W)
) u_core (
    .i_clk       (i_clk),
    .i_rstn      (i_rstn),
    .i_relu_en   (csr_out.POSTPROC_CFG.RELU_EN.value),
    .i_quant_en  (csr_out.POSTPROC_CFG.REQUANT_EN.value),
    .i_mult      (csr_out.POSTPROC_MULT.MULT.value),
    .i_shift     (csr_out.POSTPROC_SHIFT.SHIFT.value),
    .i_wdata     (i_w_rdata),
    .i_bias_shift(bias_shift),
    .i_w_shift   (w_shift),
    .i_a_data    (i_a_rdata),
    .i_a_vld     (a_vld),
    .i_a_last    (a_last),
    .i_flush     (flush),
    .o_c_vld     (c_vld),
    .o_c_last    (c_last),
    .o_c_data    (c_data)
);

endmodule
`default_nettype wire
