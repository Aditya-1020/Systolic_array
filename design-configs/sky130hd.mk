export DESIGN_NAME = accel_top
export DESIGN_NICKNAME = systolic_130
export PLATFORM = sky130hd
export SYNTH_HDL_FRONTEND = slang

export VERILOG_FILES = $(addprefix $(ROOT_DIR)/rtl/,$(shell grep -vE '^\s*(#|$$)' $(ROOT_DIR)/rtl/files.f))
export SDC_FILE = $(ROOT_DIR)/constraints/constraints.sdc

# Match rtl/cells_clkgate.v technology wrapper.
export VERILOG_DEFINES += -D OPENROAD_CLKGATE_SKY130

include $(ROOT_DIR)/design-configs/mem.mk

# export DIE_AREA = 0 0 1470 770
# export CORE_AREA = 10 10 1460 760
export CORE_UTILIZATION = 40
export CORE_ASPECT_RATIO = 1.0
export CORE_MARGIN = 2