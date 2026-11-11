# top level apb interface tming
# initial budget: 20% of apb clock period cycle

set APB_INPUTS [get_ports {i_psel i_penable i_pwrite i_pprot* i_paddr* i_pwdata* i_pstrb*}]
set APB_OUTPUTS [get_ports {o_pready o_pslverr o_prdata* o_irq}]

set_input_delay -clock $APB_CLOCK -max [expr {$APB_PERIOD * 0.20}] $APB_INPUTS

set_input_delay -clock $APB_CLOCK -min 0.000 $APB_INPUTS

set_output_delay -clock $APB_CLOCK -max [expr {$APB_PERIOD * 0.20}] $APB_OUTPUTS

set_output_delay -clock $APB_CLOCK -min 0.000 $APB_OUTPUTS

set_driving_cell -lib_cell sky130_fd_sc_hd__buf_2 -pin X $APB_INPUTS

set_load 0.050 $APB_OUTPUTS
