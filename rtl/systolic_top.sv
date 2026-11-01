`default_nettype none
module systolic_top #(
    parameter int N = 8,
    parameter int DW = 8,
    parameter int OUT_W = 32,
    parameter int Q_W = DW,
    parameter int ADDR_W = 32,
    parameter int MEM_DW = N*DW,
    parameter int MAX_RD_OUT = 4,
    parameter int MAX_WR_OUT = 4,
    parameter int MULT_W = 16,
    parameter int ACC_W = 2*DW + ((N > 1) ? $clog2(N) : 1),
    parameter int SHIFT_W = $clog2(ACC_W + MULT_W + 1) // 6
)(
    input wire i_clk,
    input wire i_rstn,

    input wire s_apb_psel,
    input wire s_apb_penable,
    input wire s_apb_pwrite,
    input logic [2:0] s_apb_pprot,
    input logic [6:0] s_apb_paddr,
    input logic [31:0] s_apb_pwdata,
    input logic [3:0] s_apb_pstrb,
    output logic s_apb_pready,
    output logic [31:0] s_apb_prdata,
    output logic s_apb_pslverr,

    output logic o_irq,

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
    input logic mem_wr_rsp_error
);

import sysarray_csr_pkg::*; 
sysarray_csr__in_t csr_hwif_in;
sysarray_csr__out_t csr_hwif_out;

logic csr_soft_reset, csr_abort;
logic csr_load_weights, csr_start;

logic array_enable_cfg, array_enable, array_busy;
logic weights_loaded, array_stalled;
logic clk_w_en, clk_adv_en, clk_pp_en;

logic dma_busy, dma_computing, dma_done;
logic dma_err_read, dma_err_write;
logic dma_err_cfg, dma_err_cmd;

logic arr_load_w;
logic arr_start, arr_abort, arr_soft_reset;
logic signed [N*OUT_W-1:0] bias_data;

logic s_axis_w_tvalid, s_axis_w_tready;
logic [N*DW-1:0] s_axis_w_tdata;

logic s_axis_a_tvalid, s_axis_a_tlast, s_axis_a_tready;
logic [N*DW-1:0] s_axis_a_tdata;

logic m_axis_c_tlast, m_axis_c_tvalid, m_axis_c_tready;
logic [N*OUT_W-1:0] m_axis_c_tdata;

logic [MULT_W-2:0] mult_cfg; // multiplier is 15 bits usigned, postproc makes pos sign 16 bits
logic [SHIFT_W-1:0] shift_cfg;

assign csr_soft_reset= csr_hwif_out.COMMAND.SOFT_RESET.value;
assign csr_abort = csr_hwif_out.COMMAND.ABORT.value && !csr_soft_reset;
assign csr_load_weights = csr_hwif_out.COMMAND.LOAD_WEIGHTS.value && !(csr_soft_reset || csr_hwif_out.COMMAND.ABORT.value);
assign csr_start = csr_hwif_out.COMMAND.START.value && !(csr_soft_reset || csr_hwif_out.COMMAND.ABORT.value);

assign array_enable_cfg = csr_hwif_out.ARRAY_CFG.ARRAY_EN.value;
assign array_enable = array_enable_cfg || dma_busy || array_busy;
assign mult_cfg = csr_hwif_out.POSTPROC_MULT.MULT.value;
assign shift_cfg = csr_hwif_out.POSTPROC_SHIFT.SHIFT.value;


always_comb begin
    csr_hwif_in = '0;
    csr_hwif_in.STATUS.BUSY.next = dma_busy || array_busy;
    csr_hwif_in.STATUS.WEIGHTS_LOADED.next = weights_loaded;
    csr_hwif_in.STATUS.COMPUTING.next = dma_computing;
    csr_hwif_in.STATUS.STALLED.next = array_stalled;
    csr_hwif_in.STATUS.DONE.next = dma_done && !(csr_soft_reset || arr_start);
    csr_hwif_in.STATUS.DONE.hwclr = csr_soft_reset || arr_start;
    csr_hwif_in.ERROR_STATUS.READ_ERR.next = dma_err_read;
    csr_hwif_in.ERROR_STATUS.WRITE_ERR.next = dma_err_write;
    csr_hwif_in.ERROR_STATUS.CFG_ERR.next = dma_err_cfg;
    csr_hwif_in.ERROR_STATUS.CMD_ERR.next = dma_err_cmd;
    csr_hwif_in.LP_STATUS.IDLE.next = !(dma_busy || array_busy);
    csr_hwif_in.LP_STATUS.CLK_W_ON.next = clk_w_en;
    csr_hwif_in.LP_STATUS.CLK_ADV_ON.next = clk_adv_en;
    csr_hwif_in.LP_STATUS.CLK_PP_ON.next = clk_pp_en;
end

assign o_irq = (csr_hwif_out.STATUS.intr && csr_hwif_out.INT_ENABLE.DONE_IE.value) || 
             (csr_hwif_out.ERROR_STATUS.intr && csr_hwif_out.INT_ENABLE.ERROR_IE.value);

sysarray_csr u_sysarray_csr (
    .clk             (i_clk),
    .rst             (!i_rstn),
    .s_apb_psel      (s_apb_psel),
    .s_apb_penable   (s_apb_penable),
    .s_apb_pwrite    (s_apb_pwrite),
    .s_apb_pprot     (s_apb_pprot),
    .s_apb_paddr     (s_apb_paddr),
    .s_apb_pwdata    (s_apb_pwdata),
    .s_apb_pstrb     (s_apb_pstrb),
    .s_apb_pready    (s_apb_pready),
    .s_apb_prdata    (s_apb_prdata),
    .s_apb_pslverr   (s_apb_pslverr),
    .hwif_in         (csr_hwif_in),
    .hwif_out        (csr_hwif_out)
);

dma_frontend #(
    .N         (N),
    .DW        (DW),
    .OUT_W     (OUT_W),
    .Q_W       (Q_W),
    .ADDR_W    (ADDR_W),
    .MEM_DW    (MEM_DW),
    .MAX_RD_OUT(MAX_RD_OUT),
    .MAX_WR_OUT(MAX_WR_OUT)
 ) dma_frontend (
    .i_clk           (i_clk),
    .i_rstn          (i_rstn),
    .i_load_weights  (csr_load_weights),
    .i_start         (csr_start),
    .i_abort         (csr_abort),
    .i_soft_reset    (csr_soft_reset),
    .i_arr_en        (array_enable_cfg),
    .i_bias_en       (csr_hwif_out.ARRAY_CFG.BIAS_EN.value),
    .i_bias_base     (csr_hwif_out.BIAS_ADDR.ADDR.value),
    .i_weight_base   (csr_hwif_out.WEIGHT_ADDR.ADDR.value),
    .i_act_base      (csr_hwif_out.ACT_ADDR.ADDR.value),
    .i_dst_base      (csr_hwif_out.DST_ADDR.ADDR.value),
    .i_act_count     (csr_hwif_out.ACT_COUNT.COUNT.value),
    .o_busy          (dma_busy),
    .o_computing     (dma_computing),
    .o_done          (dma_done),
    .o_err_read      (dma_err_read),
    .o_err_write     (dma_err_write),
    .o_err_cfg       (dma_err_cfg),
    .o_err_cmd       (dma_err_cmd),
    .o_arr_load_w    (arr_load_w),
    .o_arr_start     (arr_start),
    .o_arr_abort     (arr_abort),
    .o_arr_soft_rst  (arr_soft_reset),
    .o_bias          (bias_data),
    .i_weights_loaded(weights_loaded),
    .i_quant_en_q    (csr_hwif_out.POSTPROC_CFG.REQUANT_EN.value),
    .mem_rd_req_valid(mem_rd_req_valid),
    .mem_rd_req_ready(mem_rd_req_ready),
    .mem_rd_req_addr (mem_rd_req_addr),
    .mem_rd_rsp_valid(mem_rd_rsp_valid),
    .mem_rd_rsp_ready(mem_rd_rsp_ready),
    .mem_rd_rsp_data (mem_rd_rsp_data),
    .mem_rd_rsp_error(mem_rd_rsp_error),
    .mem_wr_req_valid(mem_wr_req_valid),
    .mem_wr_req_ready(mem_wr_req_ready),
    .mem_wr_req_addr (mem_wr_req_addr),
    .mem_wr_req_data (mem_wr_req_data),
    .mem_wr_req_strb (mem_wr_req_strb),
    .mem_wr_rsp_valid(mem_wr_rsp_valid),
    .mem_wr_rsp_ready(mem_wr_rsp_ready),
    .mem_wr_rsp_error(mem_wr_rsp_error),
    .s_axis_w_tvalid (s_axis_w_tvalid),
    .s_axis_w_tdata  (s_axis_w_tdata),
    .s_axis_w_tready (s_axis_w_tready),
    .s_axis_a_tvalid (s_axis_a_tvalid),
    .s_axis_a_tdata  (s_axis_a_tdata),
    .s_axis_a_tlast  (s_axis_a_tlast),
    .s_axis_a_tready (s_axis_a_tready),
    .m_axis_c_tvalid (m_axis_c_tvalid),
    .m_axis_c_tdata  (m_axis_c_tdata),
    .m_axis_c_tlast  (m_axis_c_tlast),
    .m_axis_c_tready (m_axis_c_tready)
);

systolic_array #(
    .N      (N),
    .DW     (DW),
    .OUT_W  (OUT_W),
    .MULT_W (MULT_W),
    .Q_W    (Q_W),
    .ACC_W  (ACC_W),
    .SHIFT_W(SHIFT_W)
 ) systolic_array (
    .i_clk           (i_clk),
    .i_rstn          (i_rstn),
    .i_arr_en        (array_enable),
    .i_auto_gate_en  (csr_hwif_out.LP_CTRL.AUTO_GATE_EN.value),
    .i_start         (arr_start),
    .i_load_w        (arr_load_w),
    .i_abort         (arr_abort),
    .i_soft_rst      (arr_soft_reset),
    .i_relu_en       (csr_hwif_out.POSTPROC_CFG.RELU_EN.value),
    .i_quant_en      (csr_hwif_out.POSTPROC_CFG.REQUANT_EN.value),
    .i_mult          (mult_cfg[MULT_W-2:0]),
    .i_shift         (shift_cfg[SHIFT_W-1:0]),
    .i_bias          (bias_data),
    .o_busy          (array_busy),
    .o_weights_loaded(weights_loaded),
    .o_stalled       (array_stalled),
    .o_quant_en      (),
    .o_clk_w_en      (clk_w_en),
    .o_clk_adv_en    (clk_adv_en),
    .o_clk_pp_en     (clk_pp_en),
    .s_axis_w_tvalid (s_axis_w_tvalid),
    .s_axis_w_tdata  (s_axis_w_tdata),
    .s_axis_w_tready (s_axis_w_tready),
    .s_axis_a_tvalid (s_axis_a_tvalid),
    .s_axis_a_tdata  (s_axis_a_tdata),
    .s_axis_a_tlast  (s_axis_a_tlast),
    .s_axis_a_tready (s_axis_a_tready),
    .m_axis_c_tready (m_axis_c_tready),
    .m_axis_c_tvalid (m_axis_c_tvalid),
    .m_axis_c_tdata  (m_axis_c_tdata),
    .m_axis_c_tlast  (m_axis_c_tlast)
);

endmodule
`default_nettype wire
