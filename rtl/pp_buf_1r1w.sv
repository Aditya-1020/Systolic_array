`default_nettype none
module pp_buf_1r1w #(
    parameter int DW = 8,
    parameter int HALF_DEPTH = 128,
    parameter int AW = $clog2(HALF_DEPTH)
)(
    input wire i_clk,
    input wire i_rstn,
    input wire i_w_en,
    input wire [AW:0] i_w_addr,
    input wire [DW-1:0] i_w_data,
    input wire i_r_en,
    input wire [AW:0] i_r_addr,
    output logic [DW-1:0] o_r_data,
    output logic o_r_valid
);
logic [DW-1:0] rd_data [0:1];
logic r_sel_q;

genvar h;
generate
    for (h=0; h<2; h=h+1) begin : gen_half
        logic wr, rd;
        assign wr = i_w_en && (i_w_addr[AW] == 1'(h));
        assign rd = i_r_en && (i_r_addr[AW] == 1'(h));

        fakeram130_128x64 u_fakeram (
            .rd_out    (rd_data[h]),
            .addr_in   (wr ? i_w_addr[AW-1:0] : i_r_addr[AW-1:0]),
            .we_in     (wr),
            .wd_in     (i_w_data),
            .w_mask_in ({DW{1'b1}}),
            .clk       (i_clk),
            .ce_in     (wr | rd)
        );
    end
endgenerate

always_ff @(posedge i_clk or negedge i_rstn) begin
    if (!i_rstn) begin
        r_sel_q <= '0;
        o_r_valid <= '0;
    end else begin
        r_sel_q <= i_r_addr[AW];
        o_r_valid <= i_r_en;
    end
end

assign o_r_data = o_r_valid ? (r_sel_q ? rd_data[1] : rd_data[0]) : '0;

`ifndef SYNTHESIS
    initial begin
        if (DW != 64 || HALF_DEPTH != 128)
            $fatal(1, "pp_buf_1r1w: macro is 64b x 128w, got DW=%0d HALF_DEPTH=%0d", DW, HALF_DEPTH);
    end

    always @(posedge i_clk) begin
        if (i_rstn && i_w_en && i_r_en && (i_w_addr[AW] == i_r_addr[AW])) begin
            $error("ppbufsram: rd and wr to same half in one cycle");
        end
    end
`endif

endmodule
`default_nettype wire
