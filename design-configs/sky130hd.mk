PROJECT_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)

RTL_NAMES := $(shell sed \
    -e 's/[[:space:]]*#.*$$//' \
    -e '/^[[:space:]]*$$/d' \
    "$(PROJECT_RTL_FILELIST)")

export PLATFORM := sky130hd
export DESIGN_NAME := sys_top
export DESIGN_NICKNAME := systolic_array

export VERILOG_FILES := $(addprefix $(PROJECT_ROOT)/rtl/,$(RTL_NAMES))

export SDC_FILE := $(PROJECT_SDC)
export IO_CONSTRAINTS := $(PROJECT_IO_CONSTRAINTS)

export ADDITIONAL_LEFS := $(sort $(wildcard $(PROJECT_MACROS_DIR)/*/*.lef))
export ADDITIONAL_LIBS := $(sort $(wildcard $(PROJECT_MACROS_DIR)/*/*.lib))

export MACRO_PLACEMENT_TCL := $(PROJECT_MACRO_PLACEMENT)

export GDS_ALLOW_EMPTY := sram_sp_.*

export SYNTH_HDL_FRONTEND := slang

export CORE_UTILIZATION ?= 65
export CORE_ASPECT_RATIO ?= 0.90
export CORE_MARGIN ?= 2

export ABC_AREA := 0
export GPL_TIMING_DRIVEN := 1