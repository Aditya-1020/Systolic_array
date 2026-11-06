`default_nettype none
module OPENROAD_CLKGATE (
    input  wire CK,
    input  wire E,
    output wire GCK
);
`ifdef OPENROAD_CLKGATE_NANGATE45
    CLKGATE_X1 u_icg (.CK(CK), .E(E), .GCK(GCK));
`elsif OPENROAD_CLKGATE_SKY130
    sky130_fd_sc_hd__dlclkp_1 u_icg (.CLK(CK), .GATE(E), .GCLK(GCK));
`else
    assign GCK = CK;
`endif
endmodule
`default_nettype wire
