`default_nettype none
module result_writer #(
    parameter int VW = 64,
    parameter int AW = 7
)(
    input wire i_clk,
    input wire i_rstn,
    input wire i_s_tvalid,
    input wire [VW-1:0] i_s_tdata,
    input wire i_s_tlast,
    output logic o_s_tready,
    input wire [1:0] i_res_full,
    output logic o_set_full,
    output logic o_set_half,
    output logic o_w_en,
    output logic [AW:0] o_w_addr,
    output logic [VW-1:0] o_w_data
);
logic half_q, fire;
logic [AW-1:0]word_q;

assign o_s_tready = !i_res_full[half_q];
assign fire = i_s_tvalid && o_s_tready;
assign o_w_en = fire;
assign o_w_addr = {half_q, word_q};
assign o_w_data = i_s_tdata;
assign o_set_full = fire && i_s_tlast;
assign o_set_half = half_q;

always_ff @(posedge i_clk or negedge i_rstn) begin
    if (!i_rstn) begin
        half_q <= '0;
        word_q <= '0;
    end else if (fire) begin
        if (i_s_tlast) begin
            word_q <= '0;
            half_q <= ~half_q;
        end else begin
            word_q <= word_q + 1'b1;
        end
    end
end

endmodule
`default_nettype wire
