`default_nettype none
module OPENROAD_CLKGATE (
    input  wire CK,
    input  wire E,
    output wire GCK
);
    // Transparent-low latch: sample E while CK is low (ICG behavior).
    logic enable_latched;
    initial enable_latched = 1'b0;
    always_latch begin
        if (CK === 1'b0)
            enable_latched = E;
    end
    assign GCK = CK & enable_latched;
endmodule
`default_nettype wire
