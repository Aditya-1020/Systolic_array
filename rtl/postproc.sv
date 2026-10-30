// apply requant, round, shifting, saturation and relu in sequence
`default_nettype none
module postproc #(
    parameter int ACC_W = 19,
    parameter int MULT_W = 16,
    parameter int OUT_W = 8,
    parameter int PROD_W = ACC_W + MULT_W,
    parameter int SHIFT_W = $clog2(PROD_W+1)
)(
    input logic signed [ACC_W-1:0] i_data,
    input logic signed [MULT_W-1:0] i_mult,
    input logic [SHIFT_W-1:0] i_shift,
    input logic i_relu_en,
    output logic signed [OUT_W-1:0] o_data
);

logic signed [PROD_W-1:0] prod;
logic signed [PROD_W-1:0] rounded;
logic signed [OUT_W-1:0] sat;
logic signed [OUT_W-1:0] act;

requantize #(.ACC_W(ACC_W), .MULT_W(MULT_W), .PROD_W(PROD_W)) u_requant (
    .i_data (i_data), .i_mult (i_mult), .o_data (prod)
);

round #(.W(PROD_W), .SHIFT_W(SHIFT_W)) u_round (
    .i_data  (prod), .i_shift (i_shift), .o_data  (rounded)
);

saturate #(.IW(PROD_W), .OW(OUT_W)) u_sat (.i_data (rounded), .o_data (sat));
relu #(.W(OUT_W)) u_relu (.i_data (sat), .o_data (act));

assign o_data = i_relu_en ? act : sat;

endmodule
`default_nettype wire
