// apply requant, round, shifting, saturation and relu in sequence
// s1 mult, s2 orund, s3 saturate and relu
`default_nettype none
module postproc #(
    parameter int ACC_W = 19,
    parameter int MULT_W = 16,
    parameter int OUT_W = 8,
    parameter int PROD_W = ACC_W + MULT_W,
    parameter int SHIFT_W = $clog2(PROD_W+1)
)(
    input wire i_clk,
    input wire i_rstn,
    input logic i_en,
    input logic i_valid,
    input logic signed [ACC_W-1:0] i_data,
    input logic signed [MULT_W-1:0] i_mult,
    input logic [SHIFT_W-1:0] i_shift,
    input logic i_relu_en,
    output logic o_valid,
    output logic signed [OUT_W-1:0] o_data
);
localparam int VALID_LAT = 3;

logic signed [PROD_W-1:0] prod, prod_q;
logic signed [PROD_W-1:0] rounded, rounded_q;
logic signed [OUT_W-1:0] sat, act, result, o_data_q;
logic [SHIFT_W-1:0] shift_q;
logic relu1_q, relu2_q;
logic [2:0] valid_q;

// s1
requantize #(.ACC_W(ACC_W), .MULT_W(MULT_W), .PROD_W(PROD_W)) u_requant (
    .i_data (i_data), .i_mult (i_mult), .o_data (prod)
);
// s2
round #(.W(PROD_W), .SHIFT_W(SHIFT_W)) u_round (
    .i_data  (prod_q), .i_shift (shift_q), .o_data  (rounded)
);
// s3
saturate #(.IW(PROD_W), .OW(OUT_W)) u_sat (
    .i_data (rounded_q), .o_data (sat)
);

relu #(.W(OUT_W)) u_relu (
    .i_data (sat), .o_data (act)
);

assign result = relu2_q ? act : sat;

always @(posedge i_clk) begin
    if (!i_rstn) begin
        valid_q <='0;
    end else if (i_en) begin
        valid_q <= {valid_q[1:0], i_valid};
    end
end

always_ff @(posedge i_clk) begin
    if (i_en) begin
        prod_q <= prod;
        shift_q <= i_shift;
        relu1_q <= i_relu_en;
        rounded_q <= rounded;
        relu2_q <= relu1_q;
        o_data_q <= result;
    end
end

assign o_valid = valid_q[VALID_LAT-1];
assign o_data = o_data_q;

endmodule
`default_nettype wire
