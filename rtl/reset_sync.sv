`default_nettype none
module reset_sync (
    input logic clk,
    input logic arstn,
    output logic rstn_sync
);
(* ASYNC_REG = "TRUE" *) logic [1:0] sync_q;

always_ff @(posedge clk or negedge arstn) begin
    if (!arstn)
        sync_q <= 2'b00;
    else
        sync_q <= {sync_q[0], 1'b1};
end

assign rstn_sync = sync_q[1];

endmodule
`default_nettype wire
