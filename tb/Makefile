.DEFAULT_GOAL := sim

ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)
TB_DIR := $(ROOT)/tb
HELPER := $(TB_DIR)/helper
RTL ?= $(ROOT)/rtl

TOPLEVEL ?= pe
MODULE ?= test_$(TOPLEVEL)
SIM ?= verilator
PE_RTL ?= $(RTL)/pe.sv

COCOTB_TOPLEVEL := $(TOPLEVEL)
COCOTB_TEST_MODULES := $(MODULE)
SIM_BUILD := $(TB_DIR)/sim_build_$(TOPLEVEL)

ifeq ($(TOPLEVEL),pe)
VERILOG_SOURCES := $(PE_RTL)
else
VERILOG_SOURCES := $(HELPER)/cells_clkgate_sim.v $(wildcard $(RTL)/*.sv) $(HELPER)/fakeram130_128x64.sv
EXTRA_ARGS += $(TB_DIR)/lint.vlt
endif

EXTRA_ARGS += -Wall
export PYTHONPATH := $(HELPER):$(TB_DIR)$(if $(PYTHONPATH),:$(PYTHONPATH))

ifeq ($(shell command -v cocotb-config 2>/dev/null),)
$(error cocotb-config not found in PATH)
endif

ifeq ($(shell command -v $(SIM) 2>/dev/null),)
$(error Simulator '$(SIM)' not found in PATH)
endif

ifeq ($(wildcard $(PE_RTL)),)
ifeq ($(TOPLEVEL),pe)
$(error PE RTL not found: $(PE_RTL))
endif
endif

COCOTB_MAKEFILES := $(shell cocotb-config --makefiles)

include $(COCOTB_MAKEFILES)/Makefile.sim

.PHONY: list-sources cleanup

list-sources:
	@printf 'TOPLEVEL=%s MODULE=%s SIM=%s\n' '$(TOPLEVEL)' '$(MODULE)' '$(SIM)'
	@printf '%s\n' $(VERILOG_SOURCES)

cleanup:
	@$(MAKE) -f $(TB_DIR)/clean.mk TOPLEVEL=$(TOPLEVEL)
