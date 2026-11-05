`default_nettype none
module mem_arb_tb_top (
    input  logic        i_clk,
    input  logic        i_rstn,
    input  logic        i_core_req,
    input  logic        i_core_we,
    input  logic [5:0]  i_core_addr,
    input  logic [63:0] i_core_wdata,
    input  logic [63:0] i_core_wmask,
    output logic        o_core_gnt,
    output logic        o_core_rvalid,
    output logic [63:0] o_core_rdata,
    input  logic        i_sw_req,
    input  logic        i_sw_we,
    input  logic [5:0]  i_sw_addr,
    input  logic [63:0] i_sw_wdata,
    input  logic [63:0] i_sw_wmask,
    output logic        o_sw_gnt,
    output logic        o_sw_rvalid,
    output logic [63:0] o_sw_rdata
);
    logic mem_ce, mem_we;
    logic [5:0] mem_addr;
    logic [63:0] mem_wdata, mem_wmask, mem_rdata;

    mem_arb #(.ADDR_W(6), .DATA_W(64)) u_arb (
        .i_clk(i_clk), .i_rstn(i_rstn),
        .i_core_req(i_core_req), .i_core_we(i_core_we),
        .i_core_addr(i_core_addr), .i_core_wdata(i_core_wdata),
        .i_core_wmask(i_core_wmask), .o_core_gnt(o_core_gnt),
        .o_core_rvalid(o_core_rvalid), .o_core_rdata(o_core_rdata),
        .i_sw_req(i_sw_req), .i_sw_we(i_sw_we),
        .i_sw_addr(i_sw_addr), .i_sw_wdata(i_sw_wdata),
        .i_sw_wmask(i_sw_wmask), .o_sw_gnt(o_sw_gnt),
        .o_sw_rvalid(o_sw_rvalid), .o_sw_rdata(o_sw_rdata),
        .o_mem_ce(mem_ce), .o_mem_we(mem_we), .o_mem_addr(mem_addr),
        .o_mem_wdata(mem_wdata), .o_mem_wmask(mem_wmask),
        .i_mem_rdata(mem_rdata)
    );

    sram_wrap #(.DEPTH(64), .ADDR_W(6), .DATA_W(64)) u_sram (
        .i_clk(i_clk), .i_ce(mem_ce), .i_we(mem_we), .i_addr(mem_addr),
        .i_wdata(mem_wdata), .i_wmask(mem_wmask), .o_rdata(mem_rdata)
    );
endmodule
`default_nettype wire
