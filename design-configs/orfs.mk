# ORFS adapter. All project-specific values are supplied by scripts.flow.
PROJECT_ROOT ?= $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)

_required_project_vars := PROJECT_RTL_DIR PROJECT_RTL_FILELIST PROJECT_PLATFORM \
                          PROJECT_DESIGN_NAME PROJECT_DESIGN_NICKNAME PROJECT_SDC \
                          PROJECT_MACROS_DIR
$(foreach v,$(_required_project_vars),$(if $($(v)),,$(error $(v) was not supplied by scripts.flow)))

RTL_NAMES := $(shell sed -e 's/[[:space:]]*#.*$$//' -e '/^[[:space:]]*$$/d' "$(PROJECT_RTL_FILELIST)")

export PLATFORM := $(PROJECT_PLATFORM)
export DESIGN_NAME := $(PROJECT_DESIGN_NAME)
export DESIGN_NICKNAME := $(PROJECT_DESIGN_NICKNAME)
export VERILOG_FILES := $(addprefix $(PROJECT_RTL_DIR)/,$(RTL_NAMES))
export SDC_FILE := $(PROJECT_SDC)
export IO_CONSTRAINTS := $(PROJECT_IO_CONSTRAINTS)
export ADDITIONAL_LEFS := $(sort $(foreach m,$(PROJECT_MACRO_MODELS),$(wildcard $(PROJECT_MACROS_DIR)/$(m)/$(m).lef)))
export ADDITIONAL_LIBS := $(sort $(foreach m,$(PROJECT_MACRO_MODELS),$(wildcard $(PROJECT_MACROS_DIR)/$(m)/$(m).lib)))
export VERILOG_FILES_BLACKBOX := $(sort $(foreach m,$(PROJECT_MACRO_MODELS),$(wildcard $(PROJECT_MACROS_DIR)/$(m)/$(m).bb.v)))

ifneq ($(strip $(PROJECT_MACRO_PLACEMENT)),)
export MACRO_PLACEMENT_TCL := $(PROJECT_MACRO_PLACEMENT)
endif

export SYNTH_HDL_FRONTEND := slang
export CORE_UTILIZATION ?= 65
export CORE_ASPECT_RATIO ?= 0.90
export CORE_MARGIN ?= 2
export ABC_AREA := 0
export GPL_TIMING_DRIVEN := 1
