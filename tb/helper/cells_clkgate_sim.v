// Simulation-only clock-gate model. Not for synthesis.
`default_nettype none
// Simulation-only, latch-based clock gate model. Use the SKY130 cell wrapper
// in synthesis/implementation, not this file.
module OPENROAD_CLKGATE (
    input  wire CK,
    input  wire E,
    output wire GCK
);
    logic enable_latched;
    always_latch begin
        if (!CK) enable_latched = E;
    end
    assign GCK = CK & enable_latched;
endmodule
`default_nettype wire
