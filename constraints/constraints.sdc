current_design systolic_top
set clk_name clk
set clk_port_name i_clk
set clk_period 10.0
set clk_io_pct 0.2
set clk_port [get_ports $clk_port_name]

set rstn_port_name i_rstn
set rstn_port [get_ports $rstn_port_name]

set non_clock_inputs [all_inputs -no_clocks]
set non_clock_inputs [remove_from_collection $non_clock_inputs $rstn_port]

set io_delay [expr {$clk_period * $clk_io_pct}]

create_clock -name $clk_name -period $clk_period $clk_port

set_false_path -from $rstn_port
set_input_delay $io_delay -clock $clk_name $non_clock_inputs
set_output_delay $io_delay -clock $clk_name [all_outputs]

# set clk_uncertainty_setup 0.2
# set clk_uncertainty_hold 0.1

# set_clock_uncertainty -setup $clk_uncertainty_setup [all_clocks]
# set_clock_uncertainty -hold $clk_uncertainty_hold [all_clocks]