current_design sys_top

set CORE_PERIOD 5.000
set APB_PERIOD 10.000
set CORE_CLOCK core_clk
set APB_CLOCK apb_clk
set RESET_PORT i_arst_n

create_clock -name $CORE_CLOCK -period $CORE_PERIOD [get_ports i_clk_core]
create_clock -name $APB_CLOCK -period $APB_PERIOD [get_ports i_clk_apb]

set_clock_uncertainty -setup 0.250 [get_clocks [list $CORE_CLOCK $APB_CLOCK]]
set_clock_uncertainty -hold 0.100 [get_clocks {$CORE_CLOCK $APB_CLOCK}]
set_clock_transition 0.100 [get_clocks {$CORE_CLOCK $APB_CLOCK}]

set_clock_groups -asynchronous \
    -group [get_clocks $CORE_CLOCK] \
    -group [get_clocks $APB_CLOCK]

set APB_INPUTS [get_ports {i_psel i_penable i_pwrite i_pprot* i_paddr* i_pwdata* i_pstrb*}]
set APB_OUTPUTS [get_ports {o_pready o_pslverr o_prdata* o_irq}]

set_input_delay -clock $APB_CLOCK -max [expr {$APB_PERIOD * 0.20}] $APB_INPUTS
set_input_delay -clock $APB_CLOCK -min 0.000 $APB_INPUTS
set_output_delay -clock $APB_CLOCK -max [expr {$APB_PERIOD * 0.20}] $APB_OUTPUTS
set_output_delay -clock $APB_CLOCK -min 0.000 $APB_OUTPUTS

set_driving_cell -lib_cell BUF_X2 -pin Z $APB_INPUTS
set_load 0.050 $APB_OUTPUTS

set_false_path -from [get_ports $RESET_PORT]
set_max_transition 1.000 [current_design]
