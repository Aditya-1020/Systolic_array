// clock gating for yosys from orfs docs
module OPENROAD_CLKGATE (CK, E, GCK);
  input  CK;
  input  E;
  output GCK;

  // <clkgate_std_cell> latch (.CLK(CK), .GATE(E), .GCLK(GCK));
  sky130_fd_sc_hd__dlclkp latch (.CLK(CK), .GATE(E), .GCLK(GCK));

endmodule
