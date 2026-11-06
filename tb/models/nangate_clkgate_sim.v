`default_nettype none
// Nangate45 ICG sim models (CK/E/GCK). Enable sampled on negedge CK.
// Build with -DNANGATE_CLKGATE_SIM so PDK CLKGATE_* bodies are skipped.

module CLKGATE_X1 (CK, E, GCK);
    input  CK;
    input  E;
    output GCK;
    reg enable_latched;
    initial enable_latched = 1'b0;
    always @(negedge CK) enable_latched <= E;
    assign GCK = CK & enable_latched;
endmodule

module CLKGATE_X2 (CK, E, GCK);
    input  CK;
    input  E;
    output GCK;
    reg enable_latched;
    initial enable_latched = 1'b0;
    always @(negedge CK) enable_latched <= E;
    assign GCK = CK & enable_latched;
endmodule

module CLKGATE_X4 (CK, E, GCK);
    input  CK;
    input  E;
    output GCK;
    reg enable_latched;
    initial enable_latched = 1'b0;
    always @(negedge CK) enable_latched <= E;
    assign GCK = CK & enable_latched;
endmodule

module CLKGATE_X8 (CK, E, GCK);
    input  CK;
    input  E;
    output GCK;
    reg enable_latched;
    initial enable_latched = 1'b0;
    always @(negedge CK) enable_latched <= E;
    assign GCK = CK & enable_latched;
endmodule

module CLKGATETST_X1 (CK, E, SE, GCK);
    input  CK;
    input  E;
    input  SE;
    output GCK;
    reg enable_latched;
    initial enable_latched = 1'b0;
    always @(negedge CK) enable_latched <= (E | SE);
    assign GCK = CK & enable_latched;
endmodule

module CLKGATETST_X2 (CK, E, SE, GCK);
    input  CK;
    input  E;
    input  SE;
    output GCK;
    reg enable_latched;
    initial enable_latched = 1'b0;
    always @(negedge CK) enable_latched <= (E | SE);
    assign GCK = CK & enable_latched;
endmodule

module CLKGATETST_X4 (CK, E, SE, GCK);
    input  CK;
    input  E;
    input  SE;
    output GCK;
    reg enable_latched;
    initial enable_latched = 1'b0;
    always @(negedge CK) enable_latched <= (E | SE);
    assign GCK = CK & enable_latched;
endmodule

module CLKGATETST_X8 (CK, E, SE, GCK);
    input  CK;
    input  E;
    input  SE;
    output GCK;
    reg enable_latched;
    initial enable_latched = 1'b0;
    always @(negedge CK) enable_latched <= (E | SE);
    assign GCK = CK & enable_latched;
endmodule

`default_nettype wire
