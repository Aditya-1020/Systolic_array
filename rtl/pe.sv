`default_nettype none
module pe #(
    parameter int DW = 8,
    parameter int ACC_W = 19
)(
    input wire i_clk,
    input wire i_rstn,
    input wire i_en,
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
assign prod_ext = ACC_W'(prod);

always_ff @(posedge i_clk) begin
    if (i_load_en) begin
        o_w <= i_w;
    end
end

always_ff @(posedge i_clk or negedge i_rstn) begin
    if (!i_rstn) begin
        o_a <='0; o_psum <= '0;
    end else if (i_en) begin
        o_a <= i_a;
        o_psum <= i_psum + prod_ext;
    end else begin
        o_a <= o_a;
        o_psum <= o_psum;
    end
end

endmodule
`default_nettype wire
