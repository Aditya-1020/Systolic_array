`default_nettype none
module postproc #(
    parameter int ACC_W = 19,
    parameter int MULT_W  = 16,
    parameter int Q_W = 8,
    parameter int OUT_W = 32,
    parameter int PROD_W = ACC_W + MULT_W,
    parameter int SHIFT_W = $clog2(PROD_W+1)
)(
    input logic i_clk,
    input logic i_relu_en,
    input logic i_quant_en,
    input logic signed [ACC_W-1:0] i_data,
    input logic [MULT_W-2:0]  i_mult,
    input logic [SHIFT_W-1:0] i_shift,
    output logic signed [OUT_W-1:0] o_data
);

logic signed [ACC_W-1:0]  relu_out, c_act, mul_in;
logic signed [MULT_W-1:0] mult_pos;
logic signed [PROD_W-1:0] prod, prod_q, rounded, rounded_q;
logic signed [Q_W-1:0]    sat, sat_q;
logic [SHIFT_W-1:0] shift_q;

// ReLU path (bypass mux)
relu #(.W(ACC_W)) u_relu (
    .i_data (i_data), .o_data (relu_out)
);

assign c_act = i_relu_en ? relu_out : i_data;

// s1
assign mul_in = i_quant_en ? c_act : '0;
assign mult_pos = {1'b0, i_mult};

requantize #(.ACC_W(ACC_W), .MULT_W(MULT_W), .PROD_W(PROD_W)) u_requant (
    .i_data (mul_in), .i_mult (mult_pos), .o_data (prod)
);

// s2
round #(.W(PROD_W), .SHIFT_W(SHIFT_W)) u_round (
    .i_data(prod_q), .i_shift (shift_q), .o_data(rounded)
);

// s3
saturate #(.IW(PROD_W), .OW(Q_W)) u_sat (
    .i_data (rounded_q), .o_data (sat)
);

always_ff @(posedge i_clk) begin
    prod_q <= prod;
    shift_q <= i_shift;
    rounded_q <= rounded;
    sat_q <= sat;
end

assign o_data = i_quant_en ? OUT_W'(sat_q) : OUT_W'(c_act);

endmodule
`default_nettype wire
