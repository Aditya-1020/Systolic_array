// 2FF level synchronizer
`default_nettype none
module cdc_sync_bit (
    input logic clk,
    input logic rstn,
    input logic i_async,
    output logic o_sync
);
(* ASYNC_REG = "TRUE" *) logic [1:0] sync_q;
always_ff @(posedge clk) begin
    if (!rstn) begin
        sync_q <= 2'b00;
    end else begin
        sync_q <= {sync_q[0], i_async};
    end
end
assign o_sync = sync_q[1];
endmodule
`default_nettype wire
