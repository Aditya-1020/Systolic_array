//sim only
module OPENROAD_CLKGATE (input CK, input E, output GCK);
  reg e_lat = 1'b0;
  always @(CK or E) if (!CK) e_lat = E;  // latch is transparent while clock is low
  assign GCK = CK & e_lat;
endmodule
