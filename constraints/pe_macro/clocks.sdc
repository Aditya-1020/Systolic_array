# pe macro clock definition
current_design pe

set PE_PERIOD 5.000
set PE_CLK_W   pe_clk_w
set PE_CLK_ADV pe_clk_adv

create_clock -name $PE_CLK_W -period $PE_PERIOD -waveform {0.000 2.500} [get_ports i_clk_w]
create_clock -name $PE_CLK_ADV -period $PE_PERIOD -waveform {0.000 2.500} [get_ports i_clk_adv]

set_clock_uncertainty -setup 0.250 [get_clocks [list $PE_CLK_W $PE_CLK_ADV]]
set_clock_uncertainty -hold 0.100 [get_clocks [list $PE_CLK_W $PE_CLK_ADV]]

set_clock_transition 0.100 [get_clocks [list $PE_CLK_W $PE_CLK_ADV]]
