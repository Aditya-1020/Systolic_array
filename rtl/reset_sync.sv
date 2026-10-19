`default_nettype none
module reset_sync (
    input wire clk,
    input wire arstn,
    output wire rstn_sync
);
logic [1:0] sync_ff; // (* ASYNC_REG = "TRUE" *)

always_ff @(posedge clk or negedge arstn) begin
    if (!arstn) begin
        sync_ff <= '0;
    end else begin
        sync_ff <= {sync_ff[0], 1'b1};
    end
end

assign rstn_sync = sync_ff[1];

endmodule
`default_nettype wire
