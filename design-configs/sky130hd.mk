export PLATFORM = sky130hd
export DESIGN_NICKNAME = systolic_array
export FAKERAM_TECH = sky130
export GDS_ALLOW_EMPTY = sram_sp_.*


include $(dir $(abspath $(lastword $(MAKEFILE_LIST))))/common.mk
