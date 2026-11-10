current_design pe

set PE_PERIOD 5.000
set PE_SETUP_UNCERTAINTY 0.250
set PE_HOLD_UNCERTAINTY 0.100
set PE_TRANSITION 0.100
set PE_IO_MAX [expr {$PE_PERIOD * 0.20}]
set PE_IO_MIN 0.000

create_clock -name clk_w -period $PE_PERIOD [get_ports i_clk_w]
create_clock -name clk_adv -period $PE_PERIOD [get_ports i_clk_adv]

set_clock_uncertainty -setup $PE_SETUP_UNCERTAINTY [get_clocks {clk_w clk_adv}]
set_clock_uncertainty -hold $PE_HOLD_UNCERTAINTY [get_clocks {clk_w clk_adv}]
set_clock_transition $PE_TRANSITION [get_clocks {clk_w clk_adv}]

set_input_delay -clock clk_w -max $PE_IO_MAX [get_ports {i_w[*]}]
set_input_delay -clock clk_w -min $PE_IO_MIN [get_ports {i_w[*]}]
set_input_delay -clock clk_adv -max $PE_IO_MAX [get_ports {i_a[*] i_psum[*]}]
set_input_delay -clock clk_adv -min $PE_IO_MIN [get_ports {i_a[*] i_psum[*]}]

set_input_transition $PE_TRANSITION [get_ports {i_w[*] i_a[*] i_psum[*]}]

set_output_delay -clock clk_w -max $PE_IO_MAX [get_ports {o_w[*]}]
set_output_delay -clock clk_w -min $PE_IO_MIN [get_ports {o_w[*]}]
set_output_delay -clock clk_adv -max $PE_IO_MAX [get_ports {o_a[*] o_psum[*]}]
set_output_delay -clock clk_adv -min $PE_IO_MIN [get_ports {o_a[*] o_psum[*]}]

set_load 0.020 [all_outputs]
set_max_transition 1.000 [current_design]
