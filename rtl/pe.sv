`default_nettype none
module pe #(
    parameter int DW = 8,
    parameter int ACC_W = 19
)(
    input wire i_clk,
    input wire i_load_en, // weight load
    input wire signed [DW-1:0] i_w, // top
    input wire signed [DW-1:0] i_a, // left
    input wire signed [ACC_W-1:0] i_psum, // top
    output logic signed [DW-1:0] o_w, // bottom
    output logic signed [DW-1:0] o_a, // right
    output logic signed [ACC_W-1:0] o_psum // bottom
);
logic signed [2*DW-1:0] prod;
logic signed [ACC_W-1:0] prod_ext;
assign prod = $signed(i_a) * $signed(o_w);
assign prod_ext = prod;

always_ff @(posedge i_clk) begin
    if (i_load_en) begin
        o_w <= i_w;
    end
    o_a <= i_a;
    o_psum <= i_psum + prod_ext;
end

endmodule
`default_nettype wire
