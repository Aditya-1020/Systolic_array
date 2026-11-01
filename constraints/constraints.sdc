current_design systolic_top

set clk_period 10.0
set clk_io_pct 0.2
set io_delay [expr {$clk_period * $clk_io_pct}]

set clk_port  [get_ports i_clk]
set rstn_port [get_ports i_rstn]

create_clock -name clk -period $clk_period $clk_port

set data_inputs {}
foreach p [all_inputs] {
    set n [get_property $p name]
    if {$n ne "i_clk" && $n ne "i_rstn"} {
        lappend data_inputs $p
    }
}

set_false_path -from $rstn_port
set_input_delay  $io_delay -clock clk $data_inputs
set_output_delay $io_delay -clock clk [all_outputs]

set_load 0.05 [all_outputs]
