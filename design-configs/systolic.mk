export DESIGN_NAME ?= accel_top
export DESIGN_NICKNAME ?= sys
export SYNTH_HDL_FRONTEND = slang

export VERILOG_FILES ?= $(addprefix $(ROOT_DIR)/rtl/,$(shell grep -vE '^\s*(#|$$)' $(ROOT_DIR)/rtl/files.f))
export SDC_FILE ?= $(ROOT_DIR)/constraints/constraints.sdc

# Clock-gate cell select (rtl/cells_clkgate.v). Do not set both.
# Override: make synth CLKGATE_DEFINE=OPENROAD_CLKGATE_SKY130
ifeq ($(PLATFORM),sky130hd)
  CLKGATE_DEFINE ?= OPENROAD_CLKGATE_SKY130
  FAKERAM_MACROS := fakeram130_256x64 fakeram130_512x64
  export DIE_AREA  = 0 0 1470 770
  export CORE_AREA = 10 10 1460 760
else ifeq ($(PLATFORM),nangate45)
  CLKGATE_DEFINE ?= OPENROAD_CLKGATE_NANGATE45
  FAKERAM_MACROS := fakeram45_128x64
  export CORE_UTILIZATION ?= 40
else
  $(error Unsupported PLATFORM '$(PLATFORM)'; use sky130hd or nangate45)
endif
export VERILOG_DEFINES += -D $(CLKGATE_DEFINE)

# fakeram macros
FAKERAM_ROOT := $(ROOT_DIR)/fakeram
export ADDITIONAL_LEFS ?= $(foreach m,$(FAKERAM_MACROS),$(wildcard $(FAKERAM_ROOT)/$(m)/$(m).lef))
export ADDITIONAL_LIBS ?= $(foreach m,$(FAKERAM_MACROS),$(wildcard $(FAKERAM_ROOT)/$(m)/$(m).lib))
export ADDITIONAL_VERILOG ?= $(foreach m,$(FAKERAM_MACROS),$(wildcard $(FAKERAM_ROOT)/$(m)/$(m).bb.v))

export OPENROAD_HIERARCHICAL = 1
export SWAP_ARITH_OPERATORS  = 1
export SYNTH_OPT_HIER = 1
export PLACE_DENSITY = 0.8
export RTLMP_MIN_CHANNEL_SIZE = 20 20
export MACRO_PLACEMENT_TCL = $(ROOT_DIR)/design-configs/macro_placement.tcl
export MACRO_PLACE_HALO = 10 10
