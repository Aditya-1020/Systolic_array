// Pulse synchronizer
`default_nettype none
module cdc_pulse_sync (
    input logic src_clk,
    input logic src_rstn,
    input logic i_pulse,
    input logic dst_clk,
    input logic dst_rstn,
    output logic o_pulse
);
logic toggle_q;
logic [2:0] sync_q;

always_ff @(posedge src_clk) begin
    if (!src_rstn) begin
        toggle_q <= 1'b0;
    end else if (i_pulse) begin
        toggle_q <= ~toggle_q;
    end
end

always_ff @(posedge dst_clk) begin
    if (!dst_rstn) begin
        sync_q <= 3'b000;
    end else begin
        sync_q <= {sync_q[1:0], toggle_q};
    end
end

assign o_pulse = sync_q[2] ^ sync_q[1];
endmodule
`default_nettype wire
