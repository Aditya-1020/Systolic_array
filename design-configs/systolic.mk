export DESIGN_NAME ?= systolic_top
export DESIGN_NICKNAME ?= sys
export SYNTH_HDL_FRONTEND = slang

export VERILOG_FILES ?= $(sort $(filter-out %/cells_clkgate.v, $(shell find $(ROOT_DIR)/rtl -type f \( -name '*.v' -o -name '*.sv' \))))
export SDC_FILE ?= $(ROOT_DIR)/constraints/constraints_300mhz.sdc

# fakeram macro for the PDK in use
FAKERAM_DIR := $(ROOT_DIR)/fakeram/fakeram$(if $(filter sky130hd,$(PLATFORM)),130,45)_128x64
export MACRO_NAME ?= $(notdir $(FAKERAM_DIR))
export ADDITIONAL_LEFS ?= $(wildcard $(FAKERAM_DIR)/*.lef)
export ADDITIONAL_LIBS ?= $(wildcard $(FAKERAM_DIR)/*.lib)

ifeq ($(PLATFORM),sky130hd)
  export DIE_AREA  = 0 0 1470 770
  export CORE_AREA = 10 10 1460 760
else
  export CORE_UTILIZATION ?= 40
endif

export OPENROAD_HIERARCHICAL = 1
export SWAP_ARITH_OPERATORS  = 1
export SYNTH_OPT_HIER = 1
export PLACE_DENSITY = 0.8
export RTLMP_MIN_CHANNEL_SIZE = 20 20
# export MACRO_PLACEMENT_TCL = $(ROOT_DIR)/design-configs
export MACRO_PLACE_HALO = 10 10