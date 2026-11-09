DESIGN_CONFIG_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
ROOT_DIR ?= $(abspath $(DESIGN_CONFIG_DIR)/..)

export DESIGN_NAME = sys_top
export SYNTH_HDL_FRONTEND = slang

RTL_LIST := $(shell sed -e 's/[[:space:]]*#.*$$//' -e '/^[[:space:]]*$$/d' "$(ROOT_DIR)/rtl/files.f")
export VERILOG_FILES = $(addprefix $(ROOT_DIR)/rtl/,$(RTL_LIST)) $(ROOT_DIR)/rtl/cells_clkgate.v
export SDC_FILE = $(ROOT_DIR)/constraints/constraints_$(PLATFORM).sdc

FAKERAM_TECH ?= $(if $(filter sky130hd,$(PLATFORM)),sky130,$(PLATFORM))
FAKERAM_DIR := $(ROOT_DIR)/fakeram/$(FAKERAM_TECH)
MEM_MACROS := sram_sp_64x64 sram_sp_64x256

export ADDITIONAL_LEFS = $(foreach m,$(MEM_MACROS),$(FAKERAM_DIR)/$(m)/$(m).lef)
export ADDITIONAL_LIBS = $(foreach m,$(MEM_MACROS),$(FAKERAM_DIR)/$(m)/$(m).lib)

export CORE_UTILIZATION ?= 60
export CORE_ASPECT_RATIO ?= 0.90
export CORE_MARGIN ?= 2
export ABC_AREA = 0
export OPENROAD_HIERARCHICAL = 1
export GPL_TIMING_DRIVEN = 1

ifeq ($(PLATFORM),sky130hd)
SKY130_LIB_DIR ?= $(PDK_ROOT)/sky130A/libs.ref/sky130_fd_sc_hd/lib
export VERILOG_DEFINES += -D OPENROAD_CLKGATE_SKY130
export CORNERS = tt ss ff
export TT_LIB_FILES = $(SKY130_LIB_DIR)/sky130_fd_sc_hd__tt_025C_1v80.lib
export SS_LIB_FILES = $(SKY130_LIB_DIR)/sky130_fd_sc_hd__ss_100C_1v60.lib
export FF_LIB_FILES = $(SKY130_LIB_DIR)/sky130_fd_sc_hd__ff_n40C_1v95.lib
else ifeq ($(PLATFORM),nangate45)
export VERILOG_DEFINES += -D OPENROAD_CLKGATE_NANGATE45
export CORNERS = typical
else
$(error Unsupported PLATFORM '$(PLATFORM)')
endif
