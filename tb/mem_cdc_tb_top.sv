// Unit-test wrapper for the asynchronous memory CDC bridge.
`default_nettype none
module mem_cdc_tb_top (
    input logic i_clk_a,
    input logic i_rstn_a,
    input logic i_a_req,
    input logic i_a_we,
    input logic [5:0] i_a_addr,
    input logic [63:0] i_a_wdata,
    input logic [63:0] i_a_wmask,
    output logic o_a_gnt,
    output logic o_a_rvalid,
    output logic [63:0] o_a_rdata,
    input logic i_clk_b,
    input logic i_rstn_b,
    output logic o_b_req,
    output logic o_b_we,
    output logic [5:0] o_b_addr,
    output logic [63:0] o_b_wdata,
    output logic [63:0] o_b_wmask,
    input logic i_b_gnt,
    input logic i_b_rvalid,
    input logic [63:0] i_b_rdata
);
    mem_cdc #(.ADDR_W(6), .DATA_W(64), .DEPTH(4)) u_dut (
        .i_clk_a,
        .i_rstn_a,
        .i_a_req,
        .i_a_we,
        .i_a_addr,
        .i_a_wdata,
        .i_a_wmask,
        .o_a_gnt,
        .o_a_rvalid,
        .o_a_rdata,
        .i_clk_b,
        .i_rstn_b,
        .o_b_req,
        .o_b_we,
        .o_b_addr,
        .o_b_wdata,
        .o_b_wmask,
        .i_b_gnt,
        .i_b_rvalid,
        .i_b_rdata
    );
endmodule
`default_nettype wire
