PROJECT_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)

ifeq ($(strip $(PROJECT_RTL_FILELIST)),)
$(error PROJECT_RTL_FILELIST was not supplied by scripts.flow)
endif
ifeq ($(strip $(PROJECT_PLATFORM)),)
$(error PROJECT_PLATFORM was not supplied by scripts.flow)
endif
ifeq ($(strip $(PROJECT_DESIGN_NAME)),)
$(error PROJECT_DESIGN_NAME was not supplied by scripts.flow)
endif
ifeq ($(strip $(PROJECT_DESIGN_NICKNAME)),)
$(error PROJECT_DESIGN_NICKNAME was not supplied by scripts.flow)
endif

RTL_NAMES := $(shell sed \
    -e 's/[[:space:]]*#.*$$//' \
    -e '/^[[:space:]]*$$/d' \
    "$(PROJECT_RTL_FILELIST)")

export PLATFORM := $(PROJECT_PLATFORM)
export DESIGN_NAME := $(PROJECT_DESIGN_NAME)
export DESIGN_NICKNAME := $(PROJECT_DESIGN_NICKNAME)
export VERILOG_FILES := $(addprefix $(PROJECT_ROOT)/rtl/,$(RTL_NAMES))
export SDC_FILE := $(PROJECT_SDC)
export IO_CONSTRAINTS := $(PROJECT_IO_CONSTRAINTS)
export ADDITIONAL_LEFS := $(sort $(wildcard $(PROJECT_MACROS_DIR)/*/*.lef))
export ADDITIONAL_LIBS := $(sort $(wildcard $(PROJECT_MACROS_DIR)/*/*.lib))

ifneq ($(strip $(PROJECT_MACRO_PLACEMENT)),)
export MACRO_PLACEMENT_TCL := $(PROJECT_MACRO_PLACEMENT)
endif

export GDS_ALLOW_EMPTY := sram_sp_.*
export SYNTH_HDL_FRONTEND := slang
export CORE_UTILIZATION ?= 65
export CORE_ASPECT_RATIO ?= 0.90
export CORE_MARGIN ?= 2
export ABC_AREA := 0
export GPL_TIMING_DRIVEN := 1
