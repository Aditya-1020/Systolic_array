current_design sys_top

set clk_period 10.0
set io_delay   [expr {$clk_period * 0.2}]

create_clock -name clk -period $clk_period [get_ports i_clk]
set_false_path -from [get_ports i_arst_n]

set in_ports {}
foreach p [all_inputs] {
    if {[get_property $p name] ne "i_clk"} { lappend in_ports $p }
}
set_input_delay  $io_delay -clock clk $in_ports
set_output_delay $io_delay -clock clk [all_outputs]
set_load 0.05 [all_outputs]
