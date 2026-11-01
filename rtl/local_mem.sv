
`default_nettype none
module local_mem #(
    parameter logic [31:0] DMEM_BASE = 32'h1000_0000,
    parameter int unsigned DMEM_BYTES = 8192,
    parameter int MAX_RD_OUT = 4,
    parameter int AW = $clog2(DMEM_BYTES/8)
)(
    input wire i_clk,
    input wire i_rstn,

    input logic i_acc_rd_req_valid,
    output logic o_acc_rd_req_ready,
    input logic [31:0] i_acc_rd_req_addr,
    output logic o_acc_rd_rsp_valid,
    input logic i_acc_rd_rsp_ready,
    output logic [63:0] o_acc_rd_rsp_data,
    output logic o_acc_rd_rsp_error,

    input logic i_acc_wr_req_valid,
    output logic o_acc_wr_req_ready,
    input logic [31:0] i_acc_wr_req_addr,
    input logic [63:0] i_acc_wr_req_data,
    input logic [7:0] i_acc_wr_req_strb,
    output logic o_acc_wr_rsp_valid,
    input logic i_acc_wr_rsp_ready,
    output logic o_acc_wr_rsp_error,

    output logic o_r_en,
    output logic [AW-1:0] o_r_addr,
    input logic i_r_ready,
    input logic [63:0] i_r_rdata,

    output logic o_w_en,
    output logic [AW-1:0] o_w_addr,
    output logic [7:0] o_w_be,
    output logic [63:0] o_w_wdata
);
localparam int CW = $clog2(MAX_RD_OUT + 1);
localparam int PW = $clog2(MAX_RD_OUT);

function automatic logic in_range(input logic [31:0] a);
    return ((a & ~(32'(DMEM_BYTES - 1))) == DMEM_BASE);
endfunction

logic acc_rd_hit, acc_rd_ok;
logic r_grant_acc;
logic s1_acc_rd_q, s1_acc_err_q;

logic [CW-1:0] cnt_q;
logic [PW-1:0] wp_q, rp_q;
logic [64:0] fifo_q [MAX_RD_OUT];
logic fifo_push, fifo_pop;

assign acc_rd_hit = in_range(i_acc_rd_req_addr);
assign acc_rd_ok = i_acc_rd_req_valid && ((int'(cnt_q) + int'(s1_acc_rd_q)) < MAX_RD_OUT);

assign r_grant_acc = acc_rd_ok && (!acc_rd_hit || i_r_ready);

assign o_r_en = acc_rd_ok && acc_rd_hit;
assign o_r_addr = i_acc_rd_req_addr[3 +: AW];
assign o_acc_rd_req_ready = r_grant_acc;

always_ff @(posedge i_clk) begin
    if (!i_rstn) begin
        s1_acc_rd_q <= 1'b0;
        s1_acc_err_q <= 1'b0;
    end else begin
        s1_acc_rd_q <= r_grant_acc;
        s1_acc_err_q <= r_grant_acc && !acc_rd_hit;
    end
end

assign fifo_push = s1_acc_rd_q;
assign o_acc_rd_rsp_valid = (cnt_q != '0);
assign fifo_pop = o_acc_rd_rsp_valid && i_acc_rd_rsp_ready;
assign {o_acc_rd_rsp_error, o_acc_rd_rsp_data} = fifo_q[rp_q];

always_ff @(posedge i_clk) begin
    if (fifo_push)
        fifo_q[wp_q] <= {s1_acc_err_q, s1_acc_err_q ? 64'd0 : i_r_rdata};
end

always_ff @(posedge i_clk) begin
    if (!i_rstn) begin
        wp_q <= '0;
        rp_q <= '0;
        cnt_q <= '0;
    end else begin
        if (fifo_push) wp_q <= wp_q + 1'b1;
        if (fifo_pop) rp_q <= rp_q + 1'b1;
        cnt_q <= cnt_q + CW'(fifo_push) - CW'(fifo_pop);
    end
end

logic acc_wr_hit, acc_wr_ok, wr_rsp_busy;

assign wr_rsp_busy = o_acc_wr_rsp_valid && !i_acc_wr_rsp_ready;
assign acc_wr_hit = in_range(i_acc_wr_req_addr);
assign acc_wr_ok = i_acc_wr_req_valid && !wr_rsp_busy;

assign o_acc_wr_req_ready = acc_wr_ok;
assign o_w_en = acc_wr_ok && acc_wr_hit;
assign o_w_addr = i_acc_wr_req_addr[3 +: AW];
assign o_w_be = i_acc_wr_req_strb;
assign o_w_wdata = i_acc_wr_req_data;

always_ff @(posedge i_clk) begin
    if (!i_rstn) begin
        o_acc_wr_rsp_valid <= 1'b0;
        o_acc_wr_rsp_error <= 1'b0;
    end else begin
        if (acc_wr_ok) begin
            o_acc_wr_rsp_valid <= 1'b1;
            o_acc_wr_rsp_error <= !acc_wr_hit;
        end else if (i_acc_wr_rsp_ready) begin
            o_acc_wr_rsp_valid <= 1'b0;
        end
    end
end

endmodule
`default_nettype wire
