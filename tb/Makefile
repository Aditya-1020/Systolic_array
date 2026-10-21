RTL ?= ../rtl
FAKERAM ?= ../fakeram/fakeram130_128x64
CELLGATE = cells_clkgate_sim.v

SIM ?= verilator
TOPLEVEL_LANG = verilog

VERILOG_SOURCES = lint.vlt $(CELLGATE) $(wildcard $(RTL)/*.sv) $(FAKERAM)/fakeram130_128x64.v

TOPLEVEL ?= systolic_top
COCOTB_TOPLEVEL = $(TOPLEVEL)
MODULE = test_$(TOPLEVEL)
COCOTB_TEST_MODULES = $(MODULE)

SIM_BUILD = sim_build_$(TOPLEVEL)
EXTRA_ARGS += -Wall

include $(shell cocotb-config --makefiles)/Makefile.sim
