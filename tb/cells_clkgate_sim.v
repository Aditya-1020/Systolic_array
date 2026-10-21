/* verilator lint_off DECLFILENAME */
/* verilator lint_off PROCASSINIT */
/* verilator lint_off LATCH */

module OPENROAD_CLKGATE (
input  CK,
input  E,
output GCK
);
reg e_lat = 1'b0;

// Capture enable while the input clock is low.
always @(CK or E) begin
  if (!CK) begin
    e_lat = E;
  end
end

assign GCK = CK & e_lat;
endmodule

/* verilator lint_on LATCH */
/* verilator lint_on PROCASSINIT */
/* verilator lint_on DECLFILENAME */
