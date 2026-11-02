`default_nettype none
// Synthesis clock-gate wrapper. Select tech with exactly one define:
//	OPENROAD_CLKGATE_SKY130
//  OPENROAD_CLKGATE_NANGATE45
// Simulation uses tb/helper/cells_clkgate_sim.v instead (do not define either)
module OPENROAD_CLKGATE (
    input  wire CK,
    input  wire E,
    output wire GCK
);

`ifdef OPENROAD_CLKGATE_NANGATE45
CLKGATE_X1 latch (.CLK(CK), .GATE(E), .GCLK(GCK));
`elsif OPENROAD_CLKGATE_SKY130
sky130_fd_sc_hd__dlclkp_1 latch (.CLK(CK), .GATE(E), .GCLK(GCK));
`else
assign GCK = CK;
`endif

endmodule
`default_nettype wire
