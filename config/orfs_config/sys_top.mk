export DESIGN_NICKNAME = systolic_array
export DESIGN_NAME = sys_top
export PLATFORM = sky130hd

SRC_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../..)

FAKERAM_PLATFORM := $(if $(filter sky130hd,$(PLATFORM)),sky130,$(PLATFORM))
FAKERAM_DIR := $(SRC_DIR)/fakeram/$(FAKERAM_PLATFORM)

PROJECT_RTL_FILELIST := $(SRC_DIR)/rtl/files.f
RTL_NAMES := $(shell sed -e 's/[[:space:]]*#.*$$//' -e '/^[[:space:]]*$$/d' "$(PROJECT_RTL_FILELIST)")

export VERILOG_FILES := $(addprefix $(SRC_DIR)/rtl/,$(RTL_NAMES))

# SRAM physical/timing views and synthesis black boxes
export ADDITIONAL_LEFS := $(sort $(wildcard $(FAKERAM_DIR)/*/*.lef))
export ADDITIONAL_LIBS := $(sort $(wildcard $(FAKERAM_DIR)/*/*.lib))
export VERILOG_FILES_BLACKBOX := $(sort $(wildcard $(FAKERAM_DIR)/*/*.bb.v))

export SDC_FILE = $(SRC_DIR)/constraints/sys_top/constraint.sdc
export IO_CONSTRAINTS = $(SRC_DIR)/constraints/sys_top/io.tcl
export PLACE_PINS_ARGS = -min_distance 10 -min_distance_in_tracks

export SYNTH_HDL_FRONTEND := slang
export CORE_UTILIZATION ?= 65
export CORE_ASPECT_RATIO ?= 0.90
export CORE_MARGIN ?= 2
export ABC_AREA := 0
export GPL_TIMING_DRIVEN := 1
export SWAP_ARITH_OPERATORS = 1
export OPENROAD_HIERARCHICAL = 1

# Placement scripts are intentionally not loaded at this stage.
