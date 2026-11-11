# pe macro interface timing constraints
# initial interface budget: 20% of the 5ns clock period
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

# activation and partial-sum interfaces
set_input_delay -clock $PE_CLK_ADV -max $PE_INPUT_MAX $PE_ADV_INPUTS
set_input_delay -clock $PE_CLK_ADV -min $PE_INPUT_MIN $PE_ADV_INPUTS

set_output_delay -clock $PE_CLK_ADV -max $PE_OUTPUT_MAX $PE_ADV_OUTPUTS
set_output_delay -clock $PE_CLK_ADV -min $PE_OUTPUT_MIN $PE_ADV_OUTPUTS

# input driver models
set_driving_cell -lib_cell sky130_fd_sc_hd__buf_2 -pin X $PE_W_INPUTS
set_driving_cell -lib_cell sky130_fd_sc_hd__buf_2 -pin X $PE_ADV_INPUTS

# output load model
set PE_OUTPUT_LOAD 0.050

set_load $PE_OUTPUT_LOAD $PE_W_OUTPUTS
set_load $PE_OUTPUT_LOAD $PE_ADV_OUTPUTS
