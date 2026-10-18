module pe #(
    parameter DW = 8,
    parameter ACC_W = 32
)(
    input wire i_clk,
    input wire i_load_w,
    input wire signed [DW-1:0] i_w, // north
    input wire signed [DW-1:0] i_a,  // west
    input wire signed [ACC_W-1:0] i_psum, // north
    output logic signed [DW-1:0] o_w, // south
    output logic signed [DW-1:0] o_a, // east
    output logic signed [DW-1:0] o_psum // south
);
logic signed [DW-1:0] w_q; // stationary weight
logic signed [2*DW-1:0] prod_q; // s1 mult
logic signed [ACC_W-1:0] psum_d; // alignment delay

always_ff @(posedge i_clk) begin
    if (i_load_w) begin
        w_q <= i_w;
    end
    o_a <= i_a;
    prod_q <= i_a * w_q; // s1
    psum_d <= i_psum;
    o_psum <= psum_d + prod_q; // s2
end

assign o_w = w_q;

endmodule
