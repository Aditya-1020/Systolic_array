`default_nettype none
module sys_top #(
    parameter int APB_AW = 14
) (
    input logic i_clk,
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
localparam int DATA_W = sys_pkg::p_beat_w;
 
logic rstn;
logic csr_psel, csr_penable, csr_pwrite, csr_pready, csr_pslverr;
logic [2:0] csr_pprot;
logic [5:0] csr_paddr;
logic [31:0] csr_pwdata, csr_prdata;
logic [3:0] csr_pstrb;
sys_csr_pkg::sys_csr__in_t csr_hwif_in;
sys_csr_pkg::sys_csr__out_t csr_hwif_out;

logic busy, run_start, done_set, err_set;
sys_pkg::ctrl_state_t seq_state;
logic pp_en, relu_en;
logic [SH_W-1:0] shift;
logic [ACC_W-1:0] round_const;
logic [RBUF_AW-1:0] caddr;
logic [ROW_W-1:0] count;
sys_pkg::output_mode_t res_mode;
 
// datapath
logic w_load, a_advance, a_valid;
logic [DATA_W-1:0] a_data;
logic [BEAT_W-1:0] beat;
logic c_valid, pp_valid, all_written;
logic [N*ACC_W-1:0] c_data;
logic [N*DW-1:0] pp_data;
 
// WBUF channel
logic wbuf_core_req, wbuf_core_rvalid;
logic [WBUF_AW-1:0] wbuf_core_addr;
logic [DATA_W-1:0] wbuf_core_rdata;
logic wbuf_sw_req, wbuf_sw_we, wbuf_sw_gnt, wbuf_sw_rvalid;
logic [WBUF_AW-1:0] wbuf_sw_addr;
logic [DATA_W-1:0] wbuf_sw_wdata, wbuf_sw_wmask, wbuf_sw_rdata;
logic wbuf_mem_ce, wbuf_mem_we;
logic [WBUF_AW-1:0] wbuf_mem_addr;
logic [DATA_W-1:0] wbuf_mem_wdata, wbuf_mem_wmask, wbuf_mem_rdata;
 
// ABUF channel
logic abuf_core_req, abuf_core_rvalid;
logic [ABUF_AW-1:0] abuf_core_addr;
logic [DATA_W-1:0] abuf_core_rdata;
logic abuf_sw_req, abuf_sw_we, abuf_sw_gnt, abuf_sw_rvalid;
logic [ABUF_AW-1:0] abuf_sw_addr;
logic [DATA_W-1:0] abuf_sw_wdata, abuf_sw_wmask, abuf_sw_rdata;
logic abuf_mem_ce, abuf_mem_we;
logic [ABUF_AW-1:0] abuf_mem_addr;
logic [DATA_W-1:0] abuf_mem_wdata, abuf_mem_wmask, abuf_mem_rdata;
 
// RBUF channel
logic rbuf_core_req;
logic [RBUF_AW-1:0] rbuf_core_addr;
logic [DATA_W-1:0] rbuf_core_wdata, rbuf_core_wmask;
logic rbuf_sw_req, rbuf_sw_we, rbuf_sw_gnt, rbuf_sw_rvalid;
logic [RBUF_AW-1:0] rbuf_sw_addr;
logic [DATA_W-1:0] rbuf_sw_wdata, rbuf_sw_wmask, rbuf_sw_rdata;
logic rbuf_mem_ce, rbuf_mem_we;
logic [RBUF_AW-1:0] rbuf_mem_addr;
logic [DATA_W-1:0] rbuf_mem_wdata, rbuf_mem_wmask, rbuf_mem_rdata;
logic irq_q;
reset_sync u_reset_sync (.clk(i_clk), .arstn(i_arst_n), .rstn_sync(rstn));

always_comb begin
    csr_hwif_in = '{default:'0};
    csr_hwif_in.STATUS.BUSY.next = busy;
    csr_hwif_in.STATUS.DONE.next = done_set;
    csr_hwif_in.STATUS.DONE.we = done_set | run_start;
    csr_hwif_in.STATUS.ERR.next = 1'b1;
    csr_hwif_in.STATUS.ERR.we = err_set;
end

always_ff @(posedge i_clk or negedge rstn) begin
    if (!rstn)
        irq_q <= 1'b0;
    else if (run_start | ~csr_hwif_out.CTRL.IRQ_EN.value)
        irq_q <= 1'b0;
    else if (done_set)
        irq_q <= 1'b1;
end
 
assign o_irq = irq_q;
 
apb_bridge #(.APB_AW(APB_AW)) u_apb_bridge (
    .i_clk         (i_clk),
    .i_rstn        (rstn),
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
    .clk           (i_clk),
    .arst_n        (rstn),
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
 
seq_ctrl #(.N(N), .ACC_W(ACC_W), .SH_W(SH_W), .ROW_W(ROW_W), .BEAT_W(BEAT_W)) u_seq_ctrl (
    .i_clk         (i_clk),
    .i_rstn        (rstn),
    .i_start       (csr_hwif_out.CTRL.START.value),
    .i_w_load_en   (csr_hwif_out.CTRL.W_LOAD.value),
    .i_waddr       (csr_hwif_out.WADDR.ADDR.value),
    .i_aaddr       (csr_hwif_out.AADDR.ADDR.value),
    .i_caddr       (csr_hwif_out.CADDR.ADDR.value),
    .i_count       (csr_hwif_out.COUNT.ROWS.value),
    .i_pp_en       (csr_hwif_out.PPCFG.PP_EN.value),
    .i_relu_en     (csr_hwif_out.PPCFG.RELU.value),
    .i_round_en    (csr_hwif_out.PPCFG.ROUND.value),
    .i_shift       (csr_hwif_out.PPCFG.SHIFT.value),
    .o_busy        (busy),
    .o_run_start   (run_start),
    .o_done_set    (done_set),
    .o_err_set     (err_set),
    .o_state       (seq_state),
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
    .o_beat        (beat),
    .i_c_valid     (c_valid),
    .i_all_written (all_written)
);
 
sys_datapath #(.N(N), .DW(DW), .ACC_W(ACC_W), .SH_W(SH_W)) u_datapath (
    .i_clk          (i_clk),
    .i_rstn         (rstn),
    .i_w_load       (w_load),
    .i_w_data       (wbuf_core_rdata),
    .i_a_advance    (a_advance),
    .i_a_valid      (a_valid),
    .i_a_data       (a_data),
    .i_post_proc_en (pp_en),
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
    .i_clk         (i_clk),
    .i_rstn        (rstn),
    .i_run_start   (run_start),
    .i_mode        (res_mode),
    .i_caddr       (caddr),
    .i_count       (count),
    .i_pp_valid    (pp_valid),
    .i_pp_data     (pp_data),
    .i_raw_valid   (c_valid & a_advance), // one result event per array advance
    .i_raw_data    (c_data),
    .i_raw_beat    (beat),
    .o_rbuf_req    (rbuf_core_req),
    .o_rbuf_addr   (rbuf_core_addr),
    .o_rbuf_wdata  (rbuf_core_wdata),
    .o_rbuf_wmask  (rbuf_core_wmask),
    .o_all_written (all_written)
);
 
// WBUF channel: array reads only
mem_arb #(.ADDR_W(WBUF_AW), .DATA_W(DATA_W)) u_wbuf_arb (
    .i_clk         (i_clk),
    .i_rstn        (rstn),
    .i_core_req    (wbuf_core_req),
    .i_core_we     (1'b0),
    .i_core_addr   (wbuf_core_addr),
    .i_core_wdata  ('0),
    .i_core_wmask  ('0),
    .o_core_gnt    (),
    .o_core_rvalid (wbuf_core_rvalid),
    .o_core_rdata  (wbuf_core_rdata),
    .i_sw_req      (wbuf_sw_req),
    .i_sw_we       (wbuf_sw_we),
    .i_sw_addr     (wbuf_sw_addr),
    .i_sw_wdata    (wbuf_sw_wdata),
    .i_sw_wmask    (wbuf_sw_wmask),
    .o_sw_gnt      (wbuf_sw_gnt),
    .o_sw_rvalid   (wbuf_sw_rvalid),
    .o_sw_rdata    (wbuf_sw_rdata),
    .o_mem_ce      (wbuf_mem_ce),
    .o_mem_we      (wbuf_mem_we),
    .o_mem_addr    (wbuf_mem_addr),
    .o_mem_wdata   (wbuf_mem_wdata),
    .o_mem_wmask   (wbuf_mem_wmask),
    .i_mem_rdata   (wbuf_mem_rdata)
);
 
sram_wrap #(.DEPTH(sys_pkg::p_wbuf_macro_depth), .ADDR_W(WBUF_AW), .DATA_W(DATA_W)) u_wbuf_mem (
    .i_clk   (i_clk),
    .i_ce    (wbuf_mem_ce),
    .i_we    (wbuf_mem_we),
    .i_addr  (wbuf_mem_addr),
    .i_wdata (wbuf_mem_wdata),
    .i_wmask (wbuf_mem_wmask),
    .o_rdata (wbuf_mem_rdata)
);
 
// ABUF channel: array reads only
mem_arb #(.ADDR_W(ABUF_AW), .DATA_W(DATA_W)) u_abuf_arb (
    .i_clk         (i_clk),
    .i_rstn        (rstn),
    .i_core_req    (abuf_core_req),
    .i_core_we     (1'b0),
    .i_core_addr   (abuf_core_addr),
    .i_core_wdata  ('0),
    .i_core_wmask  ('0),
    .o_core_gnt    (),
    .o_core_rvalid (abuf_core_rvalid),
    .o_core_rdata  (abuf_core_rdata),
    .i_sw_req      (abuf_sw_req),
    .i_sw_we       (abuf_sw_we),
    .i_sw_addr     (abuf_sw_addr),
    .i_sw_wdata    (abuf_sw_wdata),
    .i_sw_wmask    (abuf_sw_wmask),
    .o_sw_gnt      (abuf_sw_gnt),
    .o_sw_rvalid   (abuf_sw_rvalid),
    .o_sw_rdata    (abuf_sw_rdata),
    .o_mem_ce      (abuf_mem_ce),
    .o_mem_we      (abuf_mem_we),
    .o_mem_addr    (abuf_mem_addr),
    .o_mem_wdata   (abuf_mem_wdata),
    .o_mem_wmask   (abuf_mem_wmask),
    .i_mem_rdata   (abuf_mem_rdata)
);
 
sram_wrap #(.DEPTH(sys_pkg::p_abuf_depth), .ADDR_W(ABUF_AW), .DATA_W(DATA_W)) u_abuf_mem (
    .i_clk   (i_clk),
    .i_ce    (abuf_mem_ce),
    .i_we    (abuf_mem_we),
    .i_addr  (abuf_mem_addr),
    .i_wdata (abuf_mem_wdata),
    .i_wmask (abuf_mem_wmask),
    .o_rdata (abuf_mem_rdata)
);
 
// RBUF channel: array writes only, software reads
mem_arb #(.ADDR_W(RBUF_AW), .DATA_W(DATA_W)) u_rbuf_arb (
    .i_clk         (i_clk),
    .i_rstn        (rstn),
    .i_core_req    (rbuf_core_req),
    .i_core_we     (1'b1),
    .i_core_addr   (rbuf_core_addr),
    .i_core_wdata  (rbuf_core_wdata),
    .i_core_wmask  (rbuf_core_wmask),
    .o_core_gnt    (),
    .o_core_rvalid (),
    .o_core_rdata  (),
    .i_sw_req      (rbuf_sw_req),
    .i_sw_we       (rbuf_sw_we),
    .i_sw_addr     (rbuf_sw_addr),
    .i_sw_wdata    (rbuf_sw_wdata),
    .i_sw_wmask    (rbuf_sw_wmask),
    .o_sw_gnt      (rbuf_sw_gnt),
    .o_sw_rvalid   (rbuf_sw_rvalid),
    .o_sw_rdata    (rbuf_sw_rdata),
    .o_mem_ce      (rbuf_mem_ce),
    .o_mem_we      (rbuf_mem_we),
    .o_mem_addr    (rbuf_mem_addr),
    .o_mem_wdata   (rbuf_mem_wdata),
    .o_mem_wmask   (rbuf_mem_wmask),
    .i_mem_rdata   (rbuf_mem_rdata)
);
 
sram_wrap #(.DEPTH(sys_pkg::p_rbuf_depth), .ADDR_W(RBUF_AW), .DATA_W(DATA_W)) u_rbuf_mem (
    .i_clk   (i_clk),
    .i_ce    (rbuf_mem_ce),
    .i_we    (rbuf_mem_we),
    .i_addr  (rbuf_mem_addr),
    .i_wdata (rbuf_mem_wdata),
    .i_wmask (rbuf_mem_wmask),
    .o_rdata (rbuf_mem_rdata)
);
 
endmodule
`default_nettype wire
 
