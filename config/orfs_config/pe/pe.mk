export DESIGN_NICKNAME = pe
export DESIGN_NAME = pe
export PLATFORM = sky130hd

SRC_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../../..)

PE_RTL_FILELIST := $(SRC_DIR)/rtl/files_pe.f
PE_RTL_NAMES := $(shell sed -e 's/[[:space:]]*#.*$$//' -e '/^[[:space:]]*$$/d' "$(PE_RTL_FILELIST)")

export VERILOG_FILES := $(addprefix $(SRC_DIR)/rtl/,$(PE_RTL_NAMES))

export SDC_FILE = $(SRC_DIR)/constraints/pe_macro/constraint.sdc
export IO_CONSTRAINTS = $(SRC_DIR)/constraints/pe_macro/io.tcl

export PLACE_PINS_ARGS = -min_distance 10 -min_distance_in_tracks

export SYNTH_HDL_FRONTEND := slang
export GPL_TIMING_DRIVEN = 1
export ABC_AREA := 0


# FP_DIE_W ?= 165	# (original)
# FP_DIE_H ?= 165	# (original)
FP_DIE_W ?= 140
FP_DIE_H ?= 135
FP_CORE_MARGIN ?= 2

FP_CORE_X2 := $(shell expr $(FP_DIE_W) - $(FP_CORE_MARGIN))
FP_CORE_Y2 := $(shell expr $(FP_DIE_H) - $(FP_CORE_MARGIN))

export DIE_AREA = 0 0 $(FP_DIE_W) $(FP_DIE_H)

export CORE_AREA = $(FP_CORE_MARGIN) $(FP_CORE_MARGIN) $(FP_CORE_X2) $(FP_CORE_Y2)

# placement
export PLACE_DENSITY = 0.75

# export DIE_AREA = 0 0 165 165
# export CORE_AREA = 2 2 163 163
# export PLACE_DENSITY = 0.75