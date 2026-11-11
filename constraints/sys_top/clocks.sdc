# full chip clocks
# remain async unless architecture gaurantees fixed phase/freq relation
current_design sys_top

set CORE_PERIOD 5.000
set APB_PERIOD [expr {$CORE_PERIOD * 2.0}]
set CORE_CLOCK core_clk
set APB_CLOCK apb_clk

create_clock -name $CORE_CLOCK -period $CORE_PERIOD [get_ports i_clk_core]
create_clock -name $APB_CLOCK -period $APB_PERIOD [get_ports i_clk_apb]

set_clock_uncertainty -setup 0.250 [get_clocks [list $CORE_CLOCK $APB_CLOCK]]
set_clock_uncertainty -hold  0.100 [get_clocks [list $CORE_CLOCK $APB_CLOCK]]
set_clock_transition 0.100 [get_clocks [list $CORE_CLOCK $APB_CLOCK]]