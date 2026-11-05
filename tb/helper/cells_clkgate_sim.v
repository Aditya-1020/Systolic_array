`default_nettype none
// Simulation-only latch-based integrated clock-gate model.
module OPENROAD_CLKGATE (
    input  wire CK,
    input  wire E,
    output wire GCK
);
    reg enable_latched;
    initial enable_latched = 1'b0;
    always_latch begin
        if (!CK)
            enable_latched <= E;
    end
    assign GCK = CK & enable_latched;
endmodule
`default_nettype wire
