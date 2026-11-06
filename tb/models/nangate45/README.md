# Nangate45 simulation models

- `NangateOpenCellLibrary.v` — FreePDK45 / Nangate functional Verilog (Apache CCL).
  CLKGATE_* modules are wrapped in `` `ifndef NANGATE_CLKGATE_SIM `` so
  `../nangate_clkgate_sim.v` can override them for Verilator GL sims.
- Default `CELL_VERILOG` / `CELL_LIBS` for `TECH=nangate45` points here.
