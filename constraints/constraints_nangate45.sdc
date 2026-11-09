current_design sys_top

set CLK_CORE_PERIOD 5.000
set CLK_APB_DIV 2
set CLK_APB_PERIOD [expr {$CLK_CORE_PERIOD * $CLK_APB_DIV}]

set CLK_CORE_NAME clk_core
set CLK_APB_NAME clk_apb

set CLK_CORE_PORT i_clk
set RESET_PORT i_arst_n

create_clock -name $CLK_CORE_NAME -period $CLK_CORE_PERIOD [get_ports $CLK_CORE_PORT]

create_generated_clock -name $CLK_APB_NAME -master_clock [get_clocks $CLK_CORE_NAME] \
    -source [get_ports $CLK_CORE_PORT] -divide_by $CLK_APB_DIV [get_nets clk_apb]

set CLK_SETUP_UNCERTAINTY [expr {$CLK_CORE_PERIOD * 0.05}]
set CLK_HOLD_UNCERTAINTY [expr {$CLK_CORE_PERIOD * 0.02}]

set_clock_uncertainty -setup $CLK_SETUP_UNCERTAINTY [get_clocks $CLK_CORE_NAME]
set_clock_uncertainty -hold $CLK_HOLD_UNCERTAINTY [get_clocks $CLK_CORE_NAME]
set_clock_uncertainty -setup $CLK_SETUP_UNCERTAINTY [get_clocks $CLK_APB_NAME]
set_clock_uncertainty -hold $CLK_HOLD_UNCERTAINTY [get_clocks $CLK_APB_NAME]

set CLK_TRANSITION 0.100
set_clock_transition $CLK_TRANSITION [get_clocks $CLK_CORE_NAME]
set_clock_transition $CLK_TRANSITION [get_clocks $CLK_APB_NAME]

set APB_IN_PORTS [get_ports { i_psel i_penable i_pwrite i_pprot* i_paddr* i_pwdata* i_pstrb* }]
set APB_OUT_PORTS [get_ports { o_pready o_pslverr o_prdata* }]
set ALL_OUT_PORTS [get_ports { o_pready o_pslverr o_prdata* o_irq }]
set IRQ_OUT_PORT [get_ports o_irq]

set IO_IN_MAX [expr {$CLK_CORE_PERIOD * 0.20}]
set IO_IN_MIN 0.000

set_input_delay -clock $CLK_CORE_NAME -max $IO_IN_MAX $APB_IN_PORTS
set_input_delay -clock $CLK_CORE_NAME -min $IO_IN_MIN $APB_IN_PORTS

set IO_OUT_MAX [expr {$CLK_CORE_PERIOD * 0.20}]
set IO_OUT_MIN 0.000

set_output_delay -clock $CLK_CORE_NAME -max $IO_OUT_MAX $APB_OUT_PORTS
set_output_delay -clock $CLK_CORE_NAME -min $IO_OUT_MIN $APB_OUT_PORTS

set_output_delay -clock $CLK_CORE_NAME -max $IO_OUT_MAX $IRQ_OUT_PORT
set_output_delay -clock $CLK_CORE_NAME -min $IO_OUT_MIN $IRQ_OUT_PORT

set INPUT_DRIVER_CELL BUF_X2
set INPUT_DRIVER_PIN Z

set_driving_cell -lib_cell $INPUT_DRIVER_CELL -pin $INPUT_DRIVER_PIN $APB_IN_PORTS

set OUTPUT_LOAD 0.05
set_load $OUTPUT_LOAD $ALL_OUT_PORTS

set_false_path -from [get_ports $RESET_PORT]

set MAX_TRANSITION 1.000
set_max_transition $MAX_TRANSITION [current_design]


# Do not enable propagated clocks for an ideal-clock synthesis STA.
#
# For a post-CTS timing run, use propagated clocks and the actual
# clock-tree parasitics. Let the ORFS stage configuration manage
# this where applicable.
#
# Example, only when appropriate for the post-CTS STA environment:
#
# set_propagated_clock [get_clocks {
#     clk_core
#     clk_apb
# }]