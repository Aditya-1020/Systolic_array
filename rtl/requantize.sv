// fixed point multipler
`default_nettype none
module requantize #(
    parameter int ACC_W = 32,
    parameter int MULT_W = 16,
    parameter int PROD_W = ACC_W + MULT_W
)(
    input logic signed [ACC_W-1:0] i_data,
    input logic signed [MULT_W-1:0] i_mult,
    output logic signed [PROD_W-1:0] o_data
);

assign o_data = i_data * i_mult;

endmodule
`default_nettype wire
