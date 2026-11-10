export PLATFORM := sky130hd
export DESIGN_NICKNAME := systolic_array
export FAKERAM_TECH := sky130
export GDS_ALLOW_EMPTY := sram_sp_.*

export IO_CONSTRAINTS = $(DESIGN_DIR)/../constraints/pins_sky130hd.tcl
export MACRO_PLACEMENT_TCL := $(ROOT_DIR)/design-configs/placements/lshape_right.tcl

include $(dir $(abspath $(lastword $(MAKEFILE_LIST))))/common.mk
