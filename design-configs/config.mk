export PLATFORM = sky130hd
export DESIGN_NICKNAME = sys
export DESIGN_NAME = systolic_top
export SYNTH_HDL_FRONTEND = slang

export ROOT_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)

export RTL_DIR = $(ROOT_DIR)/rtl
export CONSTRAINTS_DIR = $(ROOT_DIR)/constraints
export DESIGN_CONFIGS_DIR = $(ROOT_DIR)/design-configs
export TB_DIR = $(ROOT_DIR)/tb
export VERILOG_FILES = $(sort $(shell find $(RTL_DIR) -type f \( -name "*.v" -o -name "*.sv" \)))

# macro
export FAKERAM_DIR = $(ROOT_DIR)/fakeram130_128x64
#export VERILOG_FILES += $(FAKERAM_DIR)/fakeram130_128x64.bb.v
# export ADDITIONAL_LEFS = $(FAKERAM_DIR)/fakeram130_128x64.lef
# export ADDITIONAL_LIBS = $(FAKERAM_DIR)/fakeram130_128x64.lib
export ADDITIONAL_LEFS = $(wildcard $(FAKERAM_DIR)/*.lef)
export ADDITIONAL_LIBS = $(wildcard $(FAKERAM_DIR)/*.lib)


export SDC_FILE = $(CONSTRAINTS_DIR)/$(DESIGN_NAME).sdc

# variables
# export CORE_AREA = {10 10 1500 1500}
export CORE_UTILIZATION = 50
export CORE_MARGIN = 10
export CORE_ASPECT_RATIO = 1
# export PLACE_DENSITY = 0.60

# export REMOVE_ABC_BUFFERS = 1
export OPENROAD_HIERARCHICAL = 1
export SWAP_ARITH_OPERATORS = 1
export SYNTH_OPT_HIER = 1

