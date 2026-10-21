export PLATFORM          = sky130hd
export DESIGN_NICKNAME   = sys
export DESIGN_NAME       = systolic_top
export SYNTH_HDL_FRONTEND = slang

export ROOT_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)

# cells_clkgate.v is sim-only
export VERILOG_FILES = $(sort $(filter-out %/cells_clkgate.v, $(shell find $(ROOT_DIR)/rtl -type f \( -name "*.v" -o -name "*.sv" \))))

export SDC_FILE = $(ROOT_DIR)/constraints/constraints.sdc

# fakeram macro
export ADDITIONAL_LEFS = $(wildcard $(ROOT_DIR)/fakeram/fakeram130_128x64/*.lef)
export ADDITIONAL_LIBS = $(wildcard $(ROOT_DIR)/fakeram/fakeram130_128x64/*.lib)

export CORE_UTILIZATION = 50
export CORE_MARGIN = 10
export CORE_ASPECT_RATIO = 1

export OPENROAD_HIERARCHICAL = 1
export SWAP_ARITH_OPERATORS = 1
export SYNTH_OPT_HIER = 1