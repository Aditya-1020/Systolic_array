// cdc for memory channel (apb and arbiter)
// fifo handles request and data
`default_nettype none
module mem_cdc #(
    parameter int ADDR_W = 6,
    parameter int DATA_W = 64,
    parameter int DEPTH = 4
) (
    input logic i_clk_a,
    input logic i_rstn_a,
    input logic i_a_req,
    input logic i_a_we,
    input logic [ADDR_W-1:0] i_a_addr,
    input logic [DATA_W-1:0] i_a_wdata,
    input logic [DATA_W-1:0] i_a_wmask,
    output logic o_a_gnt,
    output logic o_a_rvalid,
    output logic [DATA_W-1:0] o_a_rdata,
    input logic i_clk_b,
    input logic i_rstn_b,
    output logic o_b_req,
    output logic o_b_we,
    output logic [ADDR_W-1:0] o_b_addr,
    output logic [DATA_W-1:0] o_b_wdata,
    output logic [DATA_W-1:0] o_b_wmask,
    input logic i_b_gnt,
    input logic i_b_rvalid,
    input logic [DATA_W-1:0] i_b_rdata
);
localparam int REQ_W = 1 + ADDR_W + DATA_W + DATA_W;

logic req_full, req_empty, rsp_full, rsp_empty;
logic [REQ_W-1:0] req_wdata, req_rdata;
logic [DATA_W-1:0] rsp_rdata;
logic req_push, req_pop, rsp_push, rsp_pop;
logic a_pushed_q, b_pend_q, a_rvalid_q;
logic [DATA_W-1:0] a_rdata_q;

assign req_wdata = {i_a_we, i_a_addr, i_a_wdata, i_a_wmask};
assign req_push = i_a_req & ~req_full & ~a_pushed_q;
assign o_a_gnt = req_push;

always_ff @(posedge i_clk_a) begin
    if (!i_rstn_a) begin
        a_pushed_q <= 1'b0;
    end else if (!i_a_req) begin
        a_pushed_q <= 1'b0;
    end else if (req_push) begin
        a_pushed_q <= 1'b1;
    end
end

async_fifo #(.WIDTH(REQ_W), .DEPTH(DEPTH)) u_req_fifo (
    .wr_clk   (i_clk_a),
    .wr_rstn  (i_rstn_a),
    .wr_en    (req_push),
    .wr_data  (req_wdata),
    .wr_full  (req_full),
    .rd_clk   (i_clk_b),
    .rd_rstn  (i_rstn_b),
    .rd_en    (req_pop),
    .rd_data  (req_rdata),
    .rd_empty (req_empty)
);

assign o_b_we = req_rdata[REQ_W-1];
assign o_b_addr = req_rdata[REQ_W-2 -: ADDR_W];
assign o_b_wdata = req_rdata[2*DATA_W-1 : DATA_W];
assign o_b_wmask = req_rdata[DATA_W-1:0];
assign o_b_req = ~req_empty & ~b_pend_q;
assign req_pop = o_b_req & i_b_gnt;

always_ff @(posedge i_clk_b) begin
    if (!i_rstn_b)
        b_pend_q <= 1'b0;
    else if (o_b_req & i_b_gnt & ~o_b_we)
        b_pend_q <= 1'b1;
    else if (b_pend_q & i_b_rvalid & ~rsp_full)
        b_pend_q <= 1'b0;
end

assign rsp_push = b_pend_q & i_b_rvalid & ~rsp_full;

async_fifo #(.WIDTH(DATA_W), .DEPTH(DEPTH)) u_rsp_fifo (
    .wr_clk   (i_clk_b),
    .wr_rstn  (i_rstn_b),
    .wr_en    (rsp_push),
    .wr_data  (i_b_rdata),
    .wr_full  (rsp_full),
    .rd_clk   (i_clk_a),
    .rd_rstn  (i_rstn_a),
    .rd_en    (rsp_pop),
    .rd_data  (rsp_rdata),
    .rd_empty (rsp_empty)
);

// One-cycle rvalid pulse on APB domain (matches mem_arb).
always_ff @(posedge i_clk_a) begin
    if (!i_rstn_a) begin
        a_rvalid_q <= 1'b0;
        a_rdata_q  <= '0;
    end else if (a_rvalid_q) begin
        a_rvalid_q <= 1'b0;
    end else if (~rsp_empty) begin
        a_rvalid_q <= 1'b1;
        a_rdata_q  <= rsp_rdata;
    end
end

assign rsp_pop = ~a_rvalid_q & ~rsp_empty;
assign o_a_rvalid = a_rvalid_q;
assign o_a_rdata = a_rdata_q;

endmodule
`default_nettype wire
