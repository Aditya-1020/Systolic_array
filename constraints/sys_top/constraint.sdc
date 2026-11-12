current_design sys_top

# clock
set CORE_PERIOD 5.000
set APB_PERIOD [expr {$CORE_PERIOD * 2.0}]

set CORE_CLOCK core_clk
set APB_CLOCK apb_clk

create_clock -name $CORE_CLOCK -period $CORE_PERIOD [get_ports i_clk_core]
create_clock -name $APB_CLOCK -period $APB_PERIOD [get_ports i_clk_apb]

set_clock_uncertainty -setup 0.250 [get_clocks [list $CORE_CLOCK $APB_CLOCK]]
set_clock_uncertainty -hold 0.100 [get_clocks [list $CORE_CLOCK $APB_CLOCK]]
set_clock_transition 0.100 [get_clocks [list $CORE_CLOCK $APB_CLOCK]]

# apb interface timing
# initial budget: 20% of apb clock period
set APB_INPUTS [get_ports {
    i_psel
    i_penable
    i_pwrite
    i_pprot*
    i_paddr*
    i_pwdata*
    i_pstrb*
}]

set APB_OUTPUTS [get_ports {
    o_pready
    o_pslverr
    o_prdata*
    o_irq
}]

set_input_delay -clock $APB_CLOCK -max [expr {$APB_PERIOD * 0.20}] $APB_INPUTS

set_input_delay -clock $APB_CLOCK -min 0.000 $APB_INPUTS

set_output_delay -clock $APB_CLOCK -max [expr {$APB_PERIOD * 0.20}] $APB_OUTPUTS

set_output_delay -clock $APB_CLOCK -min 0.000 $APB_OUTPUTS

# input driver
set_driving_cell -lib_cell sky130_fd_sc_hd__buf_2 -pin X $APB_INPUTS

set_load 0.050 $APB_OUTPUTS


# timing exceptions

# apb and core clock domains are async
# all crossings through cdc structures in chip (std-cell impl)

set_clock_groups -asynchronous -group [get_clocks $CORE_CLOCK] -group [get_clocks $APB_CLOCK]

# external async reset entry
# release is synchronized in each domain with sync

set_false_path -from [get_ports i_arst_n]

set_max_transition 1.000 [current_design]
