export DESIGN_NAME = accel_top
export DESIGN_NICKNAME = systolic_45
export PLATFORM = nangate45
export SYNTH_HDL_FRONTEND = slang
export VERILOG_FILES = $(addprefix $(ROOT_DIR)/rtl/,$(shell grep -vE '^\s*(#|$$)' $(ROOT_DIR)/rtl/files.f))
export SDC_FILE = $(ROOT_DIR)/constraints/constraints.sdc
export VERILOG_DEFINES += -D OPENROAD_CLKGATE_NANGATE45

include $(ROOT_DIR)/design-configs/mem.mk
export CORE_UTILIZATION = 40