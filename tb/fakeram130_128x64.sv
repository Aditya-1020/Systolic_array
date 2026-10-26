`default_nettype none
// Simulation-only behavioral stand-in for the foundry/flow SRAM macro.
// 128 words x 64 bits, synchronous read, active-high write enable.
// Do NOT use this model for synthesis or physical implementation.
module fakeram130_128x64 (
    output logic [63:0] rd_out,
    input  wire [6:0]  addr_in,
    input  wire        we_in,
    input  wire [63:0] wd_in,
    input  wire [63:0] w_mask_in,
    input  wire        clk,
    input  wire        ce_in
);
    logic [63:0] mem [0:127];
    integer k;
    initial begin
        rd_out = '0;
        for (k = 0; k < 128; k = k + 1) mem[k] = '0;
    end
    always_ff @(posedge clk) begin
        if (ce_in) begin
            if (we_in) begin
                for (integer b = 0; b < 64; b = b + 1)
                    if (w_mask_in[b]) mem[addr_in][b] <= wd_in[b];
            end else begin
                rd_out <= mem[addr_in];
            end
        end
    end
endmodule
`default_nettype wire
