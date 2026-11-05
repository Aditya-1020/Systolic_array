// Technology macro wrapper
`default_nettype none
module sram_wrap #(
    parameter int DEPTH = sys_pkg::p_abuf_depth,
    parameter int ADDR_W = $clog2(DEPTH),
    parameter int DATA_W = sys_pkg::p_beat_w
) (
    input logic i_clk,
    input logic i_ce,
    input logic i_we,
    input logic [ADDR_W-1:0] i_addr,
    input logic [DATA_W-1:0] i_wdata,
    input logic [DATA_W-1:0] i_wmask,
    output wire  [DATA_W-1:0] o_rdata
);
generate
    if (DATA_W != 64) begin : g_bad_width
        initial $error("sram_wrap supports DATA_W=64 only");
    end

    if ((DEPTH == 64) && (ADDR_W == 6) && (DATA_W == 64)) begin : g_64x64
        sram_sp_64x64 u_mem (
            .clk       (i_clk),
            .ce_in     (i_ce),
            .we_in     (i_we),
            .addr_in   (i_addr),
            .wd_in     (i_wdata),
            .w_mask_in (i_wmask),
            .rd_out    (o_rdata)
        );
    end else if ((DEPTH == 256) && (ADDR_W == 8) && (DATA_W == 64)) begin : g_256x64
        sram_sp_64x256 u_mem (
            .clk       (i_clk),
            .ce_in     (i_ce),
            .we_in     (i_we),
            .addr_in   (i_addr),
            .wd_in     (i_wdata),
            .w_mask_in (i_wmask),
            .rd_out    (o_rdata)
        );
    end else begin : g_unsupported_geometry
        initial $error("Unsupported SRAM geometry: DEPTH=%0d ADDR_W=%0d DATA_W=%0d", DEPTH, ADDR_W, DATA_W);
        assign o_rdata = '0;
    end
endgenerate

endmodule
`default_nettype wire
