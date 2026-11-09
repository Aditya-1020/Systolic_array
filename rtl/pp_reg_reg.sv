`default_nettype none
(* keep_hierarchy *)
module pp_reg_reg #(
    parameter int W = 1
)(
    input logic i_clk,
    input logic [W-1:0] i_d,
    output logic [W-1:0] o_q
);

always_ff @(posedge i_clk) begin
    o_q <= i_d;
end

endmodule
`default_nettype wire
