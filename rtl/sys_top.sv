`default_nettype none
module sys_top #(
    parameter int APB_AW = 14
) (
    input logic i_clk_core,
    input logic i_clk_apb,
    input logic i_arst_n,
    input logic i_psel,
    input logic i_penable,
    input logic i_pwrite,
    input logic [2:0] i_pprot,
    input logic [APB_AW-1:0] i_paddr,
    input logic [31:0] i_pwdata,
    input logic [3:0] i_pstrb,
    output logic o_pready,
    output logic [31:0] o_prdata,
    output logic o_pslverr,
    output logic o_irq
);
localparam int N = sys_pkg::p_n;
localparam int DW = sys_pkg::p_dw;
localparam int ACC_W = sys_pkg::p_acc_w;
localparam int SH_W = sys_pkg::p_shift_w;
localparam int ROW_W = $clog2(sys_pkg::p_max_rows + 1);
localparam int BEAT_W = $clog2(sys_pkg::p_raw_beats);
localparam int WBUF_AW = sys_pkg::p_wbuf_macro_aw;
localparam int ABUF_AW = sys_pkg::p_abuf_aw;
localparam int RBUF_AW = sys_pkg::p_rbuf_aw;
localparam int DATA_W  = sys_pkg::p_beat_w;
// Job descriptor: {w_load, pp_en, relu, round, shift, waddr, aaddr, caddr, count}
localparam int CFG_W = 1 + 1 + 1 + 1 + SH_W + 16 + 16 + 16 + 16;

logic rstn_core;
logic rstn_apb;

reset_sync u_reset_sync_core (.clk(i_clk_core), .arstn(i_arst_n), .rstn_sync(rstn_core));
reset_sync u_reset_sync_apb  (.clk(i_clk_apb),  .arstn(i_arst_n), .rstn_sync(rstn_apb));

logic rstn_core_leaf;
logic rstn_apb_leaf;
always_ff @(posedge i_clk_core) begin
    rstn_core_leaf <= rstn_core;
end
always_ff @(posedge i_clk_apb) begin
    rstn_apb_leaf  <= rstn_apb;
end

logic csr_psel, csr_penable, csr_pwrite, csr_pready, csr_pslverr;
logic [2:0] csr_pprot;
logic [5:0] csr_paddr;
logic [31:0] csr_pwdata, csr_prdata;
logic [3:0] csr_pstrb;
sys_csr_pkg::sys_csr__in_t  csr_hwif_in;
sys_csr_pkg::sys_csr__out_t csr_hwif_out;

logic busy, run_start, done_set, err_set;
logic busy_apb, run_start_apb, done_set_apb, err_set_apb;
logic [5:0] seq_state_oh;   // {DONE, FLUSH, RUN, WLOAD, CHECK, IDLE}
logic pp_en, relu_en;
logic [SH_W-1:0] shift;
logic [ACC_W-1:0] round_const;
logic [RBUF_AW-1:0] caddr;
logic [ROW_W-1:0] count;
sys_pkg::output_mode_t res_mode;

logic w_load, a_advance, a_valid;
logic [DATA_W-1:0] a_data;
logic c_valid, pp_valid, all_written;
logic [N*ACC_W-1:0] c_data;
logic [N*DW-1:0] pp_data;

logic wbuf_core_req, wbuf_core_rvalid;
logic [WBUF_AW-1:0] wbuf_core_addr;
logic [DATA_W-1:0] wbuf_core_rdata;
logic wbuf_sw_req, wbuf_sw_we, wbuf_sw_gnt, wbuf_sw_rvalid;
logic [WBUF_AW-1:0] wbuf_sw_addr;
logic [DATA_W-1:0] wbuf_sw_wdata, wbuf_sw_wmask, wbuf_sw_rdata;
logic wbuf_mem_ce, wbuf_mem_we;
logic [WBUF_AW-1:0] wbuf_mem_addr;
logic [DATA_W-1:0] wbuf_mem_wdata, wbuf_mem_wmask, wbuf_mem_rdata;

logic abuf_core_req, abuf_core_rvalid;
logic [ABUF_AW-1:0] abuf_core_addr;
logic [DATA_W-1:0] abuf_core_rdata;
logic abuf_sw_req, abuf_sw_we, abuf_sw_gnt, abuf_sw_rvalid;
logic [ABUF_AW-1:0] abuf_sw_addr;
logic [DATA_W-1:0] abuf_sw_wdata, abuf_sw_wmask, abuf_sw_rdata;
logic abuf_mem_ce, abuf_mem_we;
logic [ABUF_AW-1:0] abuf_mem_addr;
logic [DATA_W-1:0] abuf_mem_wdata, abuf_mem_wmask, abuf_mem_rdata;

logic rbuf_core_req;
logic [RBUF_AW-1:0] rbuf_core_addr;
logic [DATA_W-1:0] rbuf_core_wdata, rbuf_core_wmask;
logic rbuf_sw_req, rbuf_sw_we, rbuf_sw_gnt, rbuf_sw_rvalid;
logic [RBUF_AW-1:0] rbuf_sw_addr;
logic [DATA_W-1:0] rbuf_sw_wdata, rbuf_sw_wmask, rbuf_sw_rdata;
logic rbuf_mem_ce, rbuf_mem_we;
logic [RBUF_AW-1:0] rbuf_mem_addr;
logic [DATA_W-1:0] rbuf_mem_wdata, rbuf_mem_wmask, rbuf_mem_rdata;

logic wbuf_cdc_req, wbuf_cdc_we, wbuf_cdc_gnt, wbuf_cdc_rvalid;
logic [WBUF_AW-1:0] wbuf_cdc_addr;
logic [DATA_W-1:0] wbuf_cdc_wdata, wbuf_cdc_wmask, wbuf_cdc_rdata;
logic abuf_cdc_req, abuf_cdc_we, abuf_cdc_gnt, abuf_cdc_rvalid;
logic [ABUF_AW-1:0] abuf_cdc_addr;
logic [DATA_W-1:0] abuf_cdc_wdata, abuf_cdc_wmask, abuf_cdc_rdata;
logic rbuf_cdc_req, rbuf_cdc_we, rbuf_cdc_gnt, rbuf_cdc_rvalid;
logic [RBUF_AW-1:0] rbuf_cdc_addr;
logic [DATA_W-1:0] rbuf_cdc_wdata, rbuf_cdc_wmask, rbuf_cdc_rdata;

logic irq_q;
logic start_q_apb, start_rise_apb, cfg_push, cfg_full;
logic [CFG_W-1:0] cfg_wdata, cfg_rdata, cfg_hold_q;
logic cfg_empty, cfg_pop;
logic start_core;
logic cfg_w_load, cfg_pp_en, cfg_relu, cfg_round;
logic [SH_W-1:0] cfg_shift;
logic [15:0] cfg_waddr, cfg_aaddr, cfg_caddr, cfg_count;

// APB domain: bridge + CSR + IRQ
always_comb begin
    csr_hwif_in = '{default: '0};
    csr_hwif_in.STATUS.BUSY.next = busy_apb;
    // Clear DONE in the APB domain on START accept (cfg_push), not only via
    // run_start CDC — otherwise a stale DONE makes software think job2 finished.
    csr_hwif_in.STATUS.DONE.next = cfg_push ? 1'b0 : done_set_apb;
    csr_hwif_in.STATUS.DONE.we   = cfg_push | done_set_apb | run_start_apb;
    csr_hwif_in.STATUS.ERR.next  = 1'b1;
    csr_hwif_in.STATUS.ERR.we    = err_set_apb;
end

always_ff @(posedge i_clk_apb) begin
    if (!rstn_apb_leaf)
        irq_q <= 1'b0;
    else if (cfg_push | run_start_apb | ~csr_hwif_out.CTRL.IRQ_EN.value)
        irq_q <= 1'b0;
    else if (done_set_apb)
        irq_q <= 1'b1;
end
assign o_irq = irq_q;

apb_bridge #(.APB_AW(APB_AW)) u_apb_bridge (
    .i_clk         (i_clk_apb),
    .i_rstn        (rstn_apb_leaf),
    .i_psel        (i_psel),
    .i_penable     (i_penable),
    .i_pwrite      (i_pwrite),
    .i_pprot       (i_pprot),
    .i_paddr       (i_paddr),
    .i_pwdata      (i_pwdata),
    .i_pstrb       (i_pstrb),
    .o_pready      (o_pready),
    .o_prdata      (o_prdata),
    .o_pslverr     (o_pslverr),
    .o_csr_psel    (csr_psel),
    .o_csr_penable (csr_penable),
    .o_csr_pwrite  (csr_pwrite),
    .o_csr_pprot   (csr_pprot),
    .o_csr_paddr   (csr_paddr),
    .o_csr_pwdata  (csr_pwdata),
    .o_csr_pstrb   (csr_pstrb),
    .i_csr_pready  (csr_pready),
    .i_csr_prdata  (csr_prdata),
    .i_csr_pslverr (csr_pslverr),
    .o_wbuf_req    (wbuf_sw_req),
    .o_wbuf_we     (wbuf_sw_we),
    .o_wbuf_addr   (wbuf_sw_addr),
    .o_wbuf_wdata  (wbuf_sw_wdata),
    .o_wbuf_wmask  (wbuf_sw_wmask),
    .i_wbuf_gnt    (wbuf_sw_gnt),
    .i_wbuf_rvalid (wbuf_sw_rvalid),
    .i_wbuf_rdata  (wbuf_sw_rdata),
    .o_abuf_req    (abuf_sw_req),
    .o_abuf_we     (abuf_sw_we),
    .o_abuf_addr   (abuf_sw_addr),
    .o_abuf_wdata  (abuf_sw_wdata),
    .o_abuf_wmask  (abuf_sw_wmask),
    .i_abuf_gnt    (abuf_sw_gnt),
    .i_abuf_rvalid (abuf_sw_rvalid),
    .i_abuf_rdata  (abuf_sw_rdata),
    .o_rbuf_req    (rbuf_sw_req),
    .o_rbuf_we     (rbuf_sw_we),
    .o_rbuf_addr   (rbuf_sw_addr),
    .o_rbuf_wdata  (rbuf_sw_wdata),
    .o_rbuf_wmask  (rbuf_sw_wmask),
    .i_rbuf_gnt    (rbuf_sw_gnt),
    .i_rbuf_rvalid (rbuf_sw_rvalid),
    .i_rbuf_rdata  (rbuf_sw_rdata)
);

sys_csr u_csr (
    .clk           (i_clk_apb),
    .arst_n        (rstn_apb_leaf),
    .s_apb_psel    (csr_psel),
    .s_apb_penable (csr_penable),
    .s_apb_pwrite  (csr_pwrite),
    .s_apb_pprot   (csr_pprot),
    .s_apb_paddr   (csr_paddr),
    .s_apb_pwdata  (csr_pwdata),
    .s_apb_pstrb   (csr_pstrb),
    .s_apb_pready  (csr_pready),
    .s_apb_prdata  (csr_prdata),
    .s_apb_pslverr (csr_pslverr),
    .hwif_in       (csr_hwif_in),
    .hwif_out      (csr_hwif_out)
);

// CDC: job config
always_ff @(posedge i_clk_apb) begin
    if (!rstn_apb_leaf) begin
        start_q_apb <= 1'b0;
    end else begin
        start_q_apb <= csr_hwif_out.CTRL.START.value;
    end
end
assign start_rise_apb = csr_hwif_out.CTRL.START.value & ~start_q_apb;

assign cfg_wdata = {
    csr_hwif_out.CTRL.W_LOAD.value,
    csr_hwif_out.PPCFG.PP_EN.value,
    csr_hwif_out.PPCFG.RELU.value,
    csr_hwif_out.PPCFG.ROUND.value,
    csr_hwif_out.PPCFG.SHIFT.value[SH_W-1:0],
    csr_hwif_out.WADDR.ADDR.value[15:0],
    csr_hwif_out.AADDR.ADDR.value[15:0],
    csr_hwif_out.CADDR.ADDR.value[15:0],
    csr_hwif_out.COUNT.ROWS.value[15:0]
};
assign cfg_push = start_rise_apb & ~cfg_full;

async_fifo #(
    .WIDTH(CFG_W),
    .DEPTH(4),
    .ONEHOT_RD(1'b1)
) u_cfg_fifo (
    .wr_clk   (i_clk_apb),
    .wr_rstn  (rstn_apb_leaf),
    .wr_en    (cfg_push),
    .wr_data  (cfg_wdata),
    .wr_full  (cfg_full),
    .rd_clk   (i_clk_core),
    .rd_rstn  (rstn_core_leaf),
    .rd_en    (cfg_pop),
    .rd_data  (cfg_rdata),
    .rd_empty (cfg_empty)
);

assign cfg_pop = ~cfg_empty & ~start_core;

always_ff @(posedge i_clk_core) begin
    if (!rstn_core_leaf) begin
        start_core <= 1'b0;
        cfg_hold_q <= '0;
    end else if (cfg_pop) begin
        start_core <= 1'b1;
        cfg_hold_q <= cfg_rdata;
    end else begin
        start_core <= 1'b0;
    end
end

assign {
    cfg_w_load, cfg_pp_en, cfg_relu, cfg_round, cfg_shift,
    cfg_waddr, cfg_aaddr, cfg_caddr, cfg_count
} = cfg_hold_q;


cdc_sync_bit u_busy_sync (
    .clk(i_clk_apb), .rstn(rstn_apb_leaf), .i_async(busy), .o_sync(busy_apb)
);
cdc_pulse_sync u_done_sync (
    .src_clk(i_clk_core), .src_rstn(rstn_core_leaf), .i_pulse(done_set),
    .dst_clk(i_clk_apb),  .dst_rstn(rstn_apb_leaf),  .o_pulse(done_set_apb)
);
cdc_pulse_sync u_err_sync (
    .src_clk(i_clk_core), .src_rstn(rstn_core_leaf), .i_pulse(err_set),
    .dst_clk(i_clk_apb),  .dst_rstn(rstn_apb_leaf),  .o_pulse(err_set_apb)
);
cdc_pulse_sync u_run_start_sync (
    .src_clk(i_clk_core), .src_rstn(rstn_core_leaf), .i_pulse(run_start),
    .dst_clk(i_clk_apb),  .dst_rstn(rstn_apb_leaf),  .o_pulse(run_start_apb)
);

// CDC: SW memory ports
mem_cdc #(.ADDR_W(WBUF_AW), .DATA_W(DATA_W)) u_wbuf_cdc (
    .i_clk_a(i_clk_apb), .i_rstn_a(rstn_apb_leaf),
    .i_a_req(wbuf_sw_req), .i_a_we(wbuf_sw_we), .i_a_addr(wbuf_sw_addr),
    .i_a_wdata(wbuf_sw_wdata), .i_a_wmask(wbuf_sw_wmask),
    .o_a_gnt(wbuf_sw_gnt), .o_a_rvalid(wbuf_sw_rvalid), .o_a_rdata(wbuf_sw_rdata),
    .i_clk_b(i_clk_core), .i_rstn_b(rstn_core_leaf),
    .o_b_req(wbuf_cdc_req), .o_b_we(wbuf_cdc_we), .o_b_addr(wbuf_cdc_addr),
    .o_b_wdata(wbuf_cdc_wdata), .o_b_wmask(wbuf_cdc_wmask),
    .i_b_gnt(wbuf_cdc_gnt), .i_b_rvalid(wbuf_cdc_rvalid), .i_b_rdata(wbuf_cdc_rdata)
);

mem_cdc #(.ADDR_W(ABUF_AW), .DATA_W(DATA_W)) u_abuf_cdc (
    .i_clk_a(i_clk_apb), .i_rstn_a(rstn_apb_leaf),
    .i_a_req(abuf_sw_req), .i_a_we(abuf_sw_we), .i_a_addr(abuf_sw_addr),
    .i_a_wdata(abuf_sw_wdata), .i_a_wmask(abuf_sw_wmask),
    .o_a_gnt(abuf_sw_gnt), .o_a_rvalid(abuf_sw_rvalid), .o_a_rdata(abuf_sw_rdata),
    .i_clk_b(i_clk_core), .i_rstn_b(rstn_core_leaf),
    .o_b_req(abuf_cdc_req), .o_b_we(abuf_cdc_we), .o_b_addr(abuf_cdc_addr),
    .o_b_wdata(abuf_cdc_wdata), .o_b_wmask(abuf_cdc_wmask),
    .i_b_gnt(abuf_cdc_gnt), .i_b_rvalid(abuf_cdc_rvalid), .i_b_rdata(abuf_cdc_rdata)
);

mem_cdc #(.ADDR_W(RBUF_AW), .DATA_W(DATA_W)) u_rbuf_cdc (
    .i_clk_a(i_clk_apb), .i_rstn_a(rstn_apb_leaf),
    .i_a_req(rbuf_sw_req), .i_a_we(rbuf_sw_we), .i_a_addr(rbuf_sw_addr),
    .i_a_wdata(rbuf_sw_wdata), .i_a_wmask(rbuf_sw_wmask),
    .o_a_gnt(rbuf_sw_gnt), .o_a_rvalid(rbuf_sw_rvalid), .o_a_rdata(rbuf_sw_rdata),
    .i_clk_b(i_clk_core), .i_rstn_b(rstn_core_leaf),
    .o_b_req(rbuf_cdc_req), .o_b_we(rbuf_cdc_we), .o_b_addr(rbuf_cdc_addr),
    .o_b_wdata(rbuf_cdc_wdata), .o_b_wmask(rbuf_cdc_wmask),
    .i_b_gnt(rbuf_cdc_gnt), .i_b_rvalid(rbuf_cdc_rvalid), .i_b_rdata(rbuf_cdc_rdata)
);

seq_ctrl #(.N(N), .ACC_W(ACC_W), .SH_W(SH_W), .ROW_W(ROW_W), .BEAT_W(BEAT_W)) u_seq_ctrl (
    .i_clk         (i_clk_core),
    .i_rstn        (rstn_core_leaf),
    .i_start       (start_core),
    .i_w_load_en   (cfg_w_load),
    .i_waddr       (cfg_waddr),
    .i_aaddr       (cfg_aaddr),
    .i_caddr       (cfg_caddr),
    .i_count       (cfg_count),
    .i_pp_en       (cfg_pp_en),
    .i_relu_en     (cfg_relu),
    .i_round_en    (cfg_round),
    .i_shift       (cfg_shift),
    .o_busy        (busy),
    .o_run_start   (run_start),
    .o_done_set    (done_set),
    .o_err_set     (err_set),
    .o_state       (),
    .o_pp_en       (pp_en),
    .o_relu_en     (relu_en),
    .o_shift       (shift),
    .o_round_const (round_const),
    .o_caddr       (caddr),
    .o_count       (count),
    .o_wbuf_req    (wbuf_core_req),
    .o_wbuf_addr   (wbuf_core_addr),
    .i_wbuf_rvalid (wbuf_core_rvalid),
    .o_abuf_req    (abuf_core_req),
    .o_abuf_addr   (abuf_core_addr),
    .i_abuf_rvalid (abuf_core_rvalid),
    .i_abuf_rdata  (abuf_core_rdata),
    .o_w_load      (w_load),
    .o_a_advance   (a_advance),
    .o_a_valid     (a_valid),
    .o_a_data      (a_data),
    .o_beat        (),
    .i_c_valid     (c_valid),
    .i_all_written (all_written),
    .o_state_oh    (seq_state_oh)
);

logic dp_active;
assign dp_active = seq_state_oh[3] | seq_state_oh[4];  // RUN | FLUSH

sys_datapath #(.N(N), .DW(DW), .ACC_W(ACC_W), .SH_W(SH_W)) u_datapath (
    .i_clk          (i_clk_core),
    .i_rstn         (rstn_core_leaf),
    .i_w_load       (w_load),
    .i_w_data       (wbuf_core_rdata),
    .i_a_advance    (a_advance),
    .i_a_valid      (a_valid),
    .i_a_data       (a_data),
    .i_clear        (run_start),
    .i_post_proc_en (pp_en & dp_active),
    .i_relu_en      (relu_en),
    .i_shift        (shift),
    .i_round_const  (round_const),
    .o_c_valid      (c_valid),
    .o_c_data       (c_data),
    .o_pp_valid     (pp_valid),
    .o_pp_data      (pp_data)
);

assign res_mode = pp_en ? sys_pkg::MODE_INT8 : sys_pkg::MODE_RAW;

res_wr #(.N(N), .DW(DW), .ACC_W(ACC_W), .ROW_W(ROW_W), .BEAT_W(BEAT_W)) u_res_wr (
    .i_clk         (i_clk_core),
    .i_rstn        (rstn_core_leaf),
    .i_run_start   (run_start),
    .i_mode        (res_mode),
    .i_caddr       (caddr),
    .i_count       (count),
    .i_pp_valid    (pp_valid),
    .i_pp_data     (pp_data),
    .i_raw_valid   (~pp_en & c_valid & dp_active & ~run_start),
    .i_raw_data    (c_data),
    .o_rbuf_req    (rbuf_core_req),
    .o_rbuf_addr   (rbuf_core_addr),
    .o_rbuf_wdata  (rbuf_core_wdata),
    .o_rbuf_wmask  (rbuf_core_wmask),
    .o_all_written (all_written)
);

mem_arb #(.ADDR_W(WBUF_AW), .DATA_W(DATA_W)) u_wbuf_arb (
    .i_clk(i_clk_core), .i_rstn(rstn_core_leaf),
    .i_core_req(wbuf_core_req), .i_core_we(1'b0), .i_core_addr(wbuf_core_addr),
    .i_core_wdata('0), .i_core_wmask('0),
    .o_core_gnt(), .o_core_rvalid(wbuf_core_rvalid), .o_core_rdata(wbuf_core_rdata),
    .i_sw_req(wbuf_cdc_req), .i_sw_we(wbuf_cdc_we), .i_sw_addr(wbuf_cdc_addr),
    .i_sw_wdata(wbuf_cdc_wdata), .i_sw_wmask(wbuf_cdc_wmask),
    .o_sw_gnt(wbuf_cdc_gnt), .o_sw_rvalid(wbuf_cdc_rvalid), .o_sw_rdata(wbuf_cdc_rdata),
    .o_mem_ce(wbuf_mem_ce), .o_mem_we(wbuf_mem_we), .o_mem_addr(wbuf_mem_addr),
    .o_mem_wdata(wbuf_mem_wdata), .o_mem_wmask(wbuf_mem_wmask), .i_mem_rdata(wbuf_mem_rdata)
);

sram_wrap #(.DEPTH(sys_pkg::p_wbuf_macro_depth), .ADDR_W(WBUF_AW), .DATA_W(DATA_W)) u_wbuf_mem (
    .i_clk(i_clk_core), .i_ce(wbuf_mem_ce), .i_we(wbuf_mem_we), .i_addr(wbuf_mem_addr),
    .i_wdata(wbuf_mem_wdata), .i_wmask(wbuf_mem_wmask), .o_rdata(wbuf_mem_rdata)
);

mem_arb #(.ADDR_W(ABUF_AW), .DATA_W(DATA_W)) u_abuf_arb (
    .i_clk(i_clk_core), .i_rstn(rstn_core_leaf),
    .i_core_req(abuf_core_req), .i_core_we(1'b0), .i_core_addr(abuf_core_addr),
    .i_core_wdata('0), .i_core_wmask('0),
    .o_core_gnt(), .o_core_rvalid(abuf_core_rvalid), .o_core_rdata(abuf_core_rdata),
    .i_sw_req(abuf_cdc_req), .i_sw_we(abuf_cdc_we), .i_sw_addr(abuf_cdc_addr),
    .i_sw_wdata(abuf_cdc_wdata), .i_sw_wmask(abuf_cdc_wmask),
    .o_sw_gnt(abuf_cdc_gnt), .o_sw_rvalid(abuf_cdc_rvalid), .o_sw_rdata(abuf_cdc_rdata),
    .o_mem_ce(abuf_mem_ce), .o_mem_we(abuf_mem_we), .o_mem_addr(abuf_mem_addr),
    .o_mem_wdata(abuf_mem_wdata), .o_mem_wmask(abuf_mem_wmask), .i_mem_rdata(abuf_mem_rdata)
);

sram_wrap #(.DEPTH(sys_pkg::p_abuf_depth), .ADDR_W(ABUF_AW), .DATA_W(DATA_W)) u_abuf_mem (
    .i_clk(i_clk_core), .i_ce(abuf_mem_ce), .i_we(abuf_mem_we), .i_addr(abuf_mem_addr),
    .i_wdata(abuf_mem_wdata), .i_wmask(abuf_mem_wmask), .o_rdata(abuf_mem_rdata)
);

mem_arb #(.ADDR_W(RBUF_AW), .DATA_W(DATA_W)) u_rbuf_arb (
    .i_clk(i_clk_core), .i_rstn(rstn_core_leaf),
    .i_core_req(rbuf_core_req), .i_core_we(1'b1), .i_core_addr(rbuf_core_addr),
    .i_core_wdata(rbuf_core_wdata), .i_core_wmask(rbuf_core_wmask),
    .o_core_gnt(), .o_core_rvalid(), .o_core_rdata(),
    .i_sw_req(rbuf_cdc_req), .i_sw_we(rbuf_cdc_we), .i_sw_addr(rbuf_cdc_addr),
    .i_sw_wdata(rbuf_cdc_wdata), .i_sw_wmask(rbuf_cdc_wmask),
    .o_sw_gnt(rbuf_cdc_gnt), .o_sw_rvalid(rbuf_cdc_rvalid), .o_sw_rdata(rbuf_cdc_rdata),
    .o_mem_ce(rbuf_mem_ce), .o_mem_we(rbuf_mem_we), .o_mem_addr(rbuf_mem_addr),
    .o_mem_wdata(rbuf_mem_wdata), .o_mem_wmask(rbuf_mem_wmask), .i_mem_rdata(rbuf_mem_rdata)
);

sram_wrap #(.DEPTH(sys_pkg::p_rbuf_depth), .ADDR_W(RBUF_AW), .DATA_W(DATA_W)) u_rbuf_mem (
    .i_clk(i_clk_core), .i_ce(rbuf_mem_ce), .i_we(rbuf_mem_we), .i_addr(rbuf_mem_addr),
    .i_wdata(rbuf_mem_wdata), .i_wmask(rbuf_mem_wmask), .o_rdata(rbuf_mem_rdata)
);

endmodule
`default_nettype wire
