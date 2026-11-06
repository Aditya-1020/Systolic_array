`default_nettype none
module sky130_fd_sc_hd__dlclkp_1 (
    output wire GCLK,
    input  wire GATE,
    input  wire CLK
);
    reg enable_latched;
    initial enable_latched = 1'b0;
    always @(negedge CLK) begin
        enable_latched <= GATE;
    end
    assign GCLK = CLK & enable_latched;
endmodule
`default_nettype wire
