# Clocking and timing contract

- `i_clk_core`: core datapath and SRAM clock, nominal period 5.000 ns (200 MHz).
- `i_clk_apb`: APB/CSR clock, nominal period 10.000 ns (100 MHz).
- The RTL contract treats these clocks as asynchronous; no phase or frequency relationship is assumed.
- `i_arst_n` is active-low asynchronous reset. Each domain uses asynchronous assertion and synchronous deassertion.
- Configuration FIFO, memory CDC bridges, busy synchronizer and pulse synchronizers are CDC boundaries. SDC asynchronous clock grouping is not a substitute for CDC verification.
- APB IO delays are provisional: 20% of the 10 ns APB period (2 ns) is allocated to external input/output delay. Replace these values when the external APB master and receiver timing are specified.
- The core currently has no direct synchronous data IO.
- Add platform-specific Gray-pointer max-delay/skew constraints where supported. Inspect CDC paths separately from ordinary STA.
