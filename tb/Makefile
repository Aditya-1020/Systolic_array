.DEFAULT_GOAL := sim

ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)
TB_DIR := $(ROOT)/tb
HELPER := $(TB_DIR)/helper
RTL := $(ROOT)/rtl

TOPLEVEL ?= systolic_array
MODULE ?= test_$(TOPLEVEL)
SIM ?= verilator
PE_RTL ?= $(RTL)/pe.sv
CELLGATE := $(HELPER)/cells_clkgate_sim.v
FAKERAM := $(HELPER)/fakeram130_128x64.sv

COCOTB_TOPLEVEL := $(TOPLEVEL)
COCOTB_TEST_MODULES := $(MODULE)
SIM_BUILD := $(TB_DIR)/sim_build_$(TOPLEVEL)
EXTRA_ARGS += -Wall

ifeq ($(TOPLEVEL),pe)
VERILOG_SOURCES := $(PE_RTL)
else
VERILOG_SOURCES := $(CELLGATE) $(wildcard $(RTL)/*.sv) $(FAKERAM)
ifneq ($(wildcard $(TB_DIR)/lint.vlt),)
EXTRA_ARGS += $(TB_DIR)/lint.vlt
endif
endif

export PYTHONPATH := $(HELPER):$(TB_DIR)$(if $(PYTHONPATH),:$(PYTHONPATH))

ifeq ($(shell command -v cocotb-config 2>/dev/null),)
$(error cocotb-config not found in PATH)
endif
ifeq ($(shell command -v $(SIM) 2>/dev/null),)
$(error Simulator '$(SIM)' not found in PATH)
endif
ifeq ($(TOPLEVEL),pe)
ifeq ($(wildcard $(PE_RTL)),)
$(error PE RTL not found: $(PE_RTL))
endif
else
ifeq ($(strip $(wildcard $(RTL)/*.sv)),)
$(error No RTL .sv files found in $(RTL))
endif
ifeq ($(wildcard $(CELLGATE)),)
$(error Clock-gate model not found: $(CELLGATE))
endif
ifeq ($(wildcard $(FAKERAM)),)
$(error Fake RAM not found: $(FAKERAM))
endif
endif

COCOTB_MAKEFILES := $(shell cocotb-config --makefiles)
ifeq ($(strip $(COCOTB_MAKEFILES)),)
$(error Failed to locate Cocotb Makefiles)
endif

include $(COCOTB_MAKEFILES)/Makefile.sim

.PHONY: clean-up list-sources

clean-up:
	$(MAKE) -f $(TB_DIR)/clean.mk TOPLEVEL=$(TOPLEVEL)

list-sources:
	@printf 'TOPLEVEL=%s MODULE=%s SIM=%s\n' '$(TOPLEVEL)' '$(MODULE)' '$(SIM)'
	@printf '%s\n' $(VERILOG_SOURCES)
