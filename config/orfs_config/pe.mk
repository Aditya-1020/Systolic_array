export DESIGN_NICKNAME = pe
export DESIGN_NAME = pe
export PLATFORM = sky130hd

SRC_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../..)

PE_RTL_FILELIST := $(SRC_DIR)/rtl/files_pe.f
PE_RTL_NAMES := $(shell sed -e 's/[[:space:]]*#.*$$//' -e '/^[[:space:]]*$$/d' "$(PE_RTL_FILELIST)")

export VERILOG_FILES := $(addprefix $(SRC_DIR)/rtl/,$(PE_RTL_NAMES))

export SDC_FILE = $(SRC_DIR)/constraints/pe_macro/constraint.sdc
export IO_CONSTRAINTS = $(SRC_DIR)/constraints/pe_macro/io.tcl

export PLACE_PINS_ARGS = -min_distance 10 -min_distance_in_tracks

export SYNTH_HDL_FRONTEND := slang
export GPL_TIMING_DRIVEN = 1
export ABC_AREA := 0
export SWAP_ARITH_OPERATORS := 1
