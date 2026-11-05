// Behavioral model for generated 64-bit single-port macros
`default_nettype none
module fakeram_64bit_core #(
    parameter integer DEPTH = 64,
    parameter integer ADDR_WIDTH = $clog2(DEPTH)
) (
    output reg  [63:0] rd_out,
    input  wire [ADDR_WIDTH-1:0] addr_in,
    input  wire we_in,
    input  wire [63:0] wd_in,
    input  wire [63:0] w_mask_in,
    input  wire clk,
    input  wire ce_in
);
    reg [63:0] mem [0:DEPTH-1];
    localparam logic [ADDR_WIDTH:0] DEPTH_LIMIT = (ADDR_WIDTH+1)'(DEPTH);
    wire [ADDR_WIDTH:0] addr_ext = {1'b0, addr_in};

    always @(posedge clk) begin
        if (ce_in) begin
            if (addr_ext < DEPTH_LIMIT) begin
                rd_out <= mem[addr_in];
                if (we_in)
                    mem[addr_in] <= (wd_in & w_mask_in) | (mem[addr_in] & ~w_mask_in);
            end else begin
                rd_out <= 'x;
            end
        end
    end
endmodule

module sram_sp_64x64 (
    output wire [63:0] rd_out,
    input wire [5:0] addr_in,
    input wire we_in,
    input wire [63:0] wd_in,
    input wire [63:0] w_mask_in,
    input wire clk,
    input wire ce_in
);
    fakeram_64bit_core #(.DEPTH(64), .ADDR_WIDTH(6)) u_core (.*);
endmodule

module sram_sp_64x256 (
    output wire [63:0] rd_out,
    input wire [7:0] addr_in,
    input wire we_in,
    input wire [63:0] wd_in,
    input wire [63:0] w_mask_in,
    input wire clk,
    input wire ce_in
);
    fakeram_64bit_core #(.DEPTH(256), .ADDR_WIDTH(8)) u_core (.*);
endmodule

// Retain geometry aliases for standalone macro-model tests.
module fakeram_64x64 (
    output wire [63:0] rd_out,
    input wire [5:0] addr_in,
    input wire we_in,
    input wire [63:0] wd_in,
    input wire [63:0] w_mask_in,
    input wire clk,
    input wire ce_in
);
    sram_sp_64x64 u_mem (.*);
endmodule

module fakeram_256x64 (
    output wire [63:0] rd_out,
    input wire [7:0] addr_in,
    input wire we_in,
    input wire [63:0] wd_in,
    input wire [63:0] w_mask_in,
    input wire clk,
    input wire ce_in
);
    sram_sp_64x256 u_mem (.*);
endmodule
`default_nettype wire
