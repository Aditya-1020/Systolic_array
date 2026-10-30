module round #(
    parameter int W = 48,
    parameter int SHIFT_W = $clog2(W+1)
)(
    input logic signed [W-1:0] i_data,
    input logic [SHIFT_W-1:0] i_shift,
    output logic signed [W-1:0] o_data
);

logic signed [W:0] shifted;
assign shifted = $signed({i_data, 1'b0}) >>> i_shift;
assign o_data = shifted[W:1] + W'(shifted[0]);
 
endmodule
`default_nettype wire
