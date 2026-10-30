`default_nettype none
module saturate #(
    parameter int IW = 48,
    parameter int OW = 8
)(
    input logic signed [IW-1:0] i_data,
    output logic signed [OW-1:0] o_data
);

generate
    if (IW > OW) begin : gen_sat
        logic [IW-OW:0] top;
        logic overflow;
        logic sign;
        assign top = i_data[IW-1:OW-1];
        assign sign = i_data[IW-1];
        assign overflow = (|top) && !(&top);
        assign o_data = overflow ? {sign, {(OW-1){!sign}}} : i_data[OW-1:0];
    end else begin : gen_extend
        assign o_data = OW'(i_data);
    end
endgenerate

endmodule
`default_nettype wire
