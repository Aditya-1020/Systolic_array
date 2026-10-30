`default_nettype none
module relu #(
    parameter int W = 32
)(
    input logic signed [W-1:0] i_data,
    output logic signed [W-1:0] o_data
);

assign o_data = i_data & {W{~i_data[W-1]}};

endmodule
`default_nettype wire
