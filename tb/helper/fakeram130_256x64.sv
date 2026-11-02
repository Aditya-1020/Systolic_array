`default_nettype none
// Simulation-only behavioral stand-in for fakeram130_256x64.
module fakeram130_256x64 (
    output logic [63:0] rd_out,
    input  wire [7:0]  addr_in,
    input  wire        we_in,
    input  wire [63:0] wd_in,
    input  wire [63:0] w_mask_in,
    input  wire        clk,
    input  wire        ce_in
);
    // cocotb/Verilator --public-flat-rw exposes mem for backdoor I/O
    logic [63:0] mem [0:255];
    integer k;
    initial begin
        rd_out = '0;
        for (k = 0; k < 256; k++) mem[k] = '0;
    end
    always_ff @(posedge clk) begin
        if (ce_in) begin
            if (we_in) begin
                for (integer b = 0; b < 64; b++)
                    if (w_mask_in[b]) mem[addr_in][b] <= wd_in[b];
            end
            rd_out <= mem[addr_in];
        end
    end
endmodule
`default_nettype wire
