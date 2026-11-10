DESIGN_CONFIG_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
ROOT_DIR ?= $(abspath $(DESIGN_CONFIG_DIR)/..)

export DESIGN_NAME := sys_top
export SYNTH_HDL_FRONTEND := slang

RTL_LIST := $(shell sed -e 's/[[:space:]]*#.*$$//' -e '/^[[:space:]]*$$/d' "$(ROOT_DIR)/rtl/files.f")
export VERILOG_FILES := $(addprefix $(ROOT_DIR)/rtl/,$(RTL_LIST))
export SDC_FILE := $(ROOT_DIR)/constraints/constraints_$(PLATFORM).sdc

FAKERAM_DIR := $(ROOT_DIR)/fakeram/$(FAKERAM_TECH)
MEM_MACROS := sram_sp_64x64 sram_sp_64x256

export ADDITIONAL_LEFS := $(foreach m,$(MEM_MACROS),$(FAKERAM_DIR)/$(m)/$(m).lef)
export ADDITIONAL_LIBS := $(foreach m,$(MEM_MACROS),$(FAKERAM_DIR)/$(m)/$(m).lib)

export CORE_UTILIZATION ?= 65
export CORE_ASPECT_RATIO ?= 0.90
export CORE_MARGIN ?= 2
export ABC_AREA := 0
export OPENROAD_HIERARCHICAL := 0
export GPL_TIMING_DRIVEN := 1

ifeq ($(filter $(PLATFORM),sky130hd nangate45),)
$(error Unsupported PLATFORM '$(PLATFORM)')
endif
