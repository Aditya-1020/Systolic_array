RTL ?= ../rtl
FAKERAM ?= ../fakeram130_128x64

SIM ?= verilator
TOPLEVEL_LANG = verilog

VERILOG_SOURCES = lint.vlt $(wildcard $(RTL)/*.sv) $(FAKERAM)/fakeram130_128x64.v

TOPLEVEL ?= systolic_top
COCOTB_TOPLEVEL = $(TOPLEVEL)
MODULE = test_$(TOPLEVEL)
COCOTB_TEST_MODULES = $(MODULE)

SIM_BUILD = sim_build_$(TOPLEVEL)
EXTRA_ARGS += -Wall
# -Wno-fatal

include $(shell cocotb-config --makefiles)/Makefile.sim
