`default_nettype none
module clock_divider (
    input logic i_clk,
    input logic i_rst_n,
    output logic o_clk_div2
);
always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        o_clk_div2 <= 1'b0;
    end else begin
        o_clk_div2 <= ~o_clk_div2;
    end
end
endmodule
`default_nettype wire
