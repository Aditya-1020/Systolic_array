`default_nettype none
module apb_bridge #(
    parameter int APB_AW = 14,
    parameter int WBUF_AW = sys_pkg::p_wbuf_macro_aw,
    parameter int ABUF_AW = sys_pkg::p_abuf_aw,
    parameter int RBUF_AW = sys_pkg::p_rbuf_aw,
    parameter int DATA_W = sys_pkg::p_beat_w
) (
    input logic i_clk,
    input logic i_rstn,
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
    output logic o_csr_psel,
    output logic o_csr_penable,
    output logic o_csr_pwrite,
    output logic [2:0] o_csr_pprot,
    output logic [5:0] o_csr_paddr,
    output logic [31:0] o_csr_pwdata,
    output logic [3:0] o_csr_pstrb,
    input logic i_csr_pready,
    input logic [31:0] i_csr_prdata,
    input logic i_csr_pslverr,
    output logic o_wbuf_req,
    output logic o_wbuf_we,
    output logic [WBUF_AW-1:0] o_wbuf_addr,
    output logic [DATA_W-1:0] o_wbuf_wdata,
    output logic [DATA_W-1:0] o_wbuf_wmask,
    input logic i_wbuf_gnt,
    input logic i_wbuf_rvalid,
    input logic [DATA_W-1:0] i_wbuf_rdata,
    output logic o_abuf_req,
    output logic o_abuf_we,
    output logic [ABUF_AW-1:0] o_abuf_addr,
    output logic [DATA_W-1:0] o_abuf_wdata,
    output logic [DATA_W-1:0] o_abuf_wmask,
    input logic i_abuf_gnt,
    input logic i_abuf_rvalid,
    input logic [DATA_W-1:0] i_abuf_rdata,
    output logic o_rbuf_req,
    output logic o_rbuf_we,
    output logic [RBUF_AW-1:0] o_rbuf_addr,
    output logic [DATA_W-1:0] o_rbuf_wdata,
    output logic [DATA_W-1:0] o_rbuf_wmask,
    input logic i_rbuf_gnt,
    input logic i_rbuf_rvalid,
    input logic [DATA_W-1:0] i_rbuf_rdata
);
localparam logic [1:0] WIN_CSR = 2'd0;
localparam logic [1:0] WIN_WBUF = 2'd1;
localparam logic [1:0] WIN_ABUF = 2'd2;
localparam logic [1:0] WIN_RBUF = 2'd3;

logic [1:0] win;
logic [8:0] beat;
logic half_hi;
logic csr_sel_live, wbuf_sel_live, abuf_sel_live, rbuf_sel_live;
logic wbuf_sel_q, abuf_sel_q, rbuf_sel_q;
logic csr_ok_live, csr_ok_q, mem_ok_live, mem_ok_q;
logic csr_sel_q, csr_access_q;
logic [8:0] beat_q;
logic half_hi_q, pwrite_q;
logic [2:0] pprot_q;
logic [5:0] paddr_q;
logic [31:0] pwdata_q;
logic [3:0] pstrb_q;
logic setup, access, bad_access;
logic sw_req, sw_gnt, sw_rvalid, rd_wait_q, rd_done_q;
logic [DATA_W-1:0] sw_rdata, sw_wdata, sw_wmask;
logic [31:0] rd_data_q;
logic [31:0] strb_mask;

logic resp_q, resp_err_q;
logic [31:0] resp_data_q;
logic csr_issue, mem_issue, bad_issue, issue;

assign win = i_paddr[13:12];
assign beat = i_paddr[11:3];
assign half_hi = i_paddr[2];
assign setup = i_psel & ~i_penable;
assign access = i_psel & i_penable;

assign csr_sel_live  = (win == WIN_CSR);
assign wbuf_sel_live = (win == WIN_WBUF);
assign abuf_sel_live = (win == WIN_ABUF);
assign rbuf_sel_live = (win == WIN_RBUF);

assign csr_ok_live = csr_sel_live & (i_paddr[11:6] == '0);
assign mem_ok_live = (wbuf_sel_live & (beat < 9'(sys_pkg::p_wbuf_macro_depth))) |
    (abuf_sel_live & (beat < 9'(sys_pkg::p_abuf_depth))) |
    (rbuf_sel_live & (beat < 9'(sys_pkg::p_rbuf_depth)) & ~i_pwrite);

always_ff @(posedge i_clk) begin
    if (!i_rstn) begin
        wbuf_sel_q <= 1'b0;
        abuf_sel_q <= 1'b0;
        rbuf_sel_q <= 1'b0;
        csr_ok_q <= 1'b0;
        mem_ok_q <= 1'b0;
        csr_sel_q <= 1'b0;
        csr_access_q <= 1'b0;
        beat_q <= '0;
        half_hi_q <= 1'b0;
        pwrite_q <= 1'b0;
        pprot_q <= '0;
        paddr_q <= '0;
        pwdata_q <= '0;
        pstrb_q <= '0;
    end else begin
        csr_access_q <= access & csr_sel_q & ~resp_q;

        if (setup) begin
            wbuf_sel_q <= wbuf_sel_live;
            abuf_sel_q <= abuf_sel_live;
            rbuf_sel_q <= rbuf_sel_live;
            csr_ok_q <= csr_ok_live;
            mem_ok_q <= mem_ok_live;
            csr_sel_q <= csr_ok_live;
            beat_q <= beat;
            half_hi_q <= half_hi;
            pwrite_q <= i_pwrite;
            pprot_q <= i_pprot;
            paddr_q <= i_paddr[5:0];
            pwdata_q <= i_pwdata;
            pstrb_q <= i_pstrb;
        end else if (!i_psel) begin
            csr_sel_q <= 1'b0;
        end
    end
end

assign bad_access = access & ~csr_ok_q & ~mem_ok_q & ~resp_q;

assign csr_issue = csr_sel_q & csr_access_q & ~resp_q & i_csr_pready;
assign mem_issue = access & mem_ok_q & ~resp_q;
assign bad_issue = bad_access;
assign issue = csr_issue | (mem_issue & (pwrite_q ? sw_gnt : rd_done_q)) | bad_issue;

assign sw_req = mem_issue & ~rd_wait_q & ~rd_done_q;

assign strb_mask = {{8{pstrb_q[3]}}, {8{pstrb_q[2]}}, {8{pstrb_q[1]}}, {8{pstrb_q[0]}}};
assign sw_wdata = {pwdata_q, pwdata_q};
assign sw_wmask = half_hi_q ? {strb_mask, 32'b0} : {32'b0, strb_mask};

assign o_wbuf_req = sw_req & wbuf_sel_q;
assign o_wbuf_we = pwrite_q;
assign o_wbuf_addr = beat_q[WBUF_AW-1:0];
assign o_wbuf_wdata = sw_wdata;
assign o_wbuf_wmask = sw_wmask;

assign o_abuf_req = sw_req & abuf_sel_q;
assign o_abuf_we = pwrite_q;
assign o_abuf_addr = beat_q[ABUF_AW-1:0];
assign o_abuf_wdata = sw_wdata;
assign o_abuf_wmask = sw_wmask;

assign o_rbuf_req = sw_req & rbuf_sel_q;
assign o_rbuf_we = pwrite_q;
assign o_rbuf_addr = beat_q[RBUF_AW-1:0];
assign o_rbuf_wdata = sw_wdata;
assign o_rbuf_wmask = sw_wmask;

always_comb begin
    sw_gnt = (wbuf_sel_q & i_wbuf_gnt) | (abuf_sel_q & i_abuf_gnt) | (rbuf_sel_q & i_rbuf_gnt);
    sw_rvalid = (wbuf_sel_q & i_wbuf_rvalid) | (abuf_sel_q & i_abuf_rvalid) | (rbuf_sel_q & i_rbuf_rvalid);
    sw_rdata = ({DATA_W{wbuf_sel_q}} & i_wbuf_rdata) | ({DATA_W{abuf_sel_q}} & i_abuf_rdata) | ({DATA_W{rbuf_sel_q}} & i_rbuf_rdata);
end

always_ff @(posedge i_clk) begin
    if (!i_rstn) begin
        rd_wait_q <= 1'b0;
        rd_done_q <= 1'b0;
        rd_data_q <= '0;
    end else if (!access) begin
        rd_wait_q <= 1'b0;
        rd_done_q <= 1'b0;
    end else if (rd_wait_q & sw_rvalid) begin
        rd_wait_q <= 1'b0;
        rd_done_q <= 1'b1;
        rd_data_q <= half_hi_q ? sw_rdata[DATA_W-1 -: 32] : sw_rdata[31:0];
    end else if (sw_req & sw_gnt & ~pwrite_q) begin
        rd_wait_q <= 1'b1;
    end
end

assign o_csr_psel = csr_sel_q & ~resp_q;
assign o_csr_penable = csr_access_q & ~resp_q;
assign o_csr_pwrite = pwrite_q;
assign o_csr_pprot = pprot_q;
assign o_csr_paddr = paddr_q;
assign o_csr_pwdata = pwdata_q;
assign o_csr_pstrb = pstrb_q;

always_ff @(posedge i_clk) begin
    if (!i_rstn) begin
        resp_q <= 1'b0;
        resp_err_q <= 1'b0;
        resp_data_q <= '0;
    end else if (!access) begin
        resp_q <= 1'b0;
    end else if (resp_q) begin
        resp_q <= 1'b1;
    end else if (csr_issue) begin
        resp_q <= 1'b1;
        resp_data_q <= i_csr_prdata;
        resp_err_q <= i_csr_pslverr;
    end else if (bad_issue) begin
        resp_q <= 1'b1;
        resp_data_q <= '0;
        resp_err_q <= 1'b1;
    end else if (mem_issue & pwrite_q & sw_gnt) begin
        resp_q <= 1'b1;
        resp_data_q <= '0;
        resp_err_q <= 1'b0;
    end else if (mem_issue & ~pwrite_q & rd_done_q) begin
        resp_q <= 1'b1;
        resp_data_q <= rd_data_q;
        resp_err_q <= 1'b0;
    end
end

assign o_pready  = resp_q;
assign o_prdata  = resp_data_q;
assign o_pslverr = resp_err_q;

endmodule
`default_nettype wire
