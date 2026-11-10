export PLATFORM := nangate45
export DESIGN_NICKNAME := systolic_array
export FAKERAM_TECH := nangate45

include $(dir $(abspath $(lastword $(MAKEFILE_LIST))))/common.mk
