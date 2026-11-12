current_design pe

# clocks
set PE_PERIOD 5.000
set PE_CLK_W   pe_clk_w
set PE_CLK_ADV pe_clk_adv

create_clock -name $PE_CLK_W -period $PE_PERIOD -waveform {0.000 2.500} [get_ports i_clk_w]
create_clock -name $PE_CLK_ADV -period $PE_PERIOD -waveform {0.000 2.500} [get_ports i_clk_adv]

set_clock_uncertainty -setup 0.250 [get_clocks [list $PE_CLK_W $PE_CLK_ADV]]
set_clock_uncertainty -hold 0.100 [get_clocks [list $PE_CLK_W $PE_CLK_ADV]]
set_clock_transition 0.100 [get_clocks [list $PE_CLK_W $PE_CLK_ADV]]

# interface timing
# initial budget: 20% of the 5ns
# refine after integrating adjacent pe macros

set PE_INPUT_MAX [expr {$PE_PERIOD * 0.20}]
set PE_INPUT_MIN 0.000
set PE_OUTPUT_MAX [expr {$PE_PERIOD * 0.20}]
set PE_OUTPUT_MIN 0.000

set PE_W_INPUTS [get_ports {i_w*}]
set PE_ADV_INPUTS [get_ports {i_a* i_psum*}]

set PE_W_OUTPUTS [get_ports {o_w*}]
set PE_ADV_OUTPUTS [get_ports {o_a* o_psum*}]

# weight interface
set_input_delay -clock $PE_CLK_W -max $PE_INPUT_MAX $PE_W_INPUTS
set_input_delay -clock $PE_CLK_W -min $PE_INPUT_MIN $PE_W_INPUTS

set_output_delay -clock $PE_CLK_W -max $PE_OUTPUT_MAX $PE_W_OUTPUTS
set_output_delay -clock $PE_CLK_W -min $PE_OUTPUT_MIN $PE_W_OUTPUTS

# activation, psum
set_input_delay -clock $PE_CLK_ADV -max $PE_INPUT_MAX $PE_ADV_INPUTS
set_input_delay -clock $PE_CLK_ADV -min $PE_INPUT_MIN $PE_ADV_INPUTS

set_output_delay -clock $PE_CLK_ADV -max $PE_OUTPUT_MAX $PE_ADV_OUTPUTS
set_output_delay -clock $PE_CLK_ADV -min $PE_OUTPUT_MIN $PE_ADV_OUTPUTS

# input driver 
set_driving_cell -lib_cell sky130_fd_sc_hd__buf_2 -pin X $PE_W_INPUTS
set_driving_cell -lib_cell sky130_fd_sc_hd__buf_2 -pin X $PE_ADV_INPUTS

set PE_OUTPUT_LOAD 0.050

set_load $PE_OUTPUT_LOAD $PE_W_OUTPUTS
set_load $PE_OUTPUT_LOAD $PE_ADV_OUTPUTS

set_max_transition 1.000 [current_design]

# no asynchronous clock groups
