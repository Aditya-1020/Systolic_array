// one port sram arbiter
`default_nettype none
module mem_arb #(
    parameter int ADDR_W = sys_pkg::p_abuf_aw,
    parameter int DATA_W = sys_pkg::p_beat_w
) (
    input logic i_clk,
    input logic i_rstn,

    input logic i_core_req,
    input logic i_core_we,
    input logic [ADDR_W-1:0] i_core_addr,
    input logic [DATA_W-1:0] i_core_wdata,
    input logic [DATA_W-1:0] i_core_wmask,
    output logic o_core_gnt,
    output logic o_core_rvalid,
    output logic [DATA_W-1:0] o_core_rdata,

    input logic i_sw_req,
    input logic i_sw_we,
    input logic [ADDR_W-1:0] i_sw_addr,
    input logic [DATA_W-1:0] i_sw_wdata,
    input logic [DATA_W-1:0] i_sw_wmask,
    output logic o_sw_gnt,
    output logic o_sw_rvalid,
    output logic [DATA_W-1:0] o_sw_rdata,
    output logic o_mem_ce,
    output logic o_mem_we,
    output logic [ADDR_W-1:0] o_mem_addr,
    output logic [DATA_W-1:0] o_mem_wdata,
    output logic [DATA_W-1:0] o_mem_wmask,
    input logic [DATA_W-1:0] i_mem_rdata
);
logic core_sel, sw_sel;
logic core_read_q, sw_read_q;

always_comb begin
    core_sel = i_rstn & i_core_req;
    sw_sel = i_rstn & i_sw_req & ~i_core_req;
    o_core_gnt = core_sel;
    o_sw_gnt = sw_sel;
    o_mem_ce = core_sel | sw_sel;
    o_mem_we = 1'b0;
    o_mem_addr = '0;
    o_mem_wdata = '0;
    o_mem_wmask = '0;

    if (core_sel) begin
        o_mem_we = i_core_we;
        o_mem_addr = i_core_addr;
        o_mem_wdata = i_core_wdata;
        o_mem_wmask = i_core_wmask;
    end else if (sw_sel) begin
        o_mem_we    = i_sw_we;
        o_mem_addr  = i_sw_addr;
        o_mem_wdata = i_sw_wdata;
        o_mem_wmask = i_sw_wmask;
    end
end

always_ff @(posedge i_clk or negedge i_rstn) begin
    if (!i_rstn) begin
        core_read_q <= 1'b0;
        sw_read_q <= 1'b0;
    end else begin
        core_read_q <= core_sel & ~i_core_we;
        sw_read_q <= sw_sel & ~i_sw_we;
    end
end

assign o_core_rvalid = core_read_q;
assign o_sw_rvalid = sw_read_q;
assign o_core_rdata = i_mem_rdata;
assign o_sw_rdata = i_mem_rdata;

endmodule
`default_nettype wire
