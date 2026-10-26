# Works whether invoked as `make -C tb` or `make -f tb/Makefile` from ROOT.
ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)
TB_DIR := $(ROOT)/tb

RTL ?= $(ROOT)/rtl
FAKERAM ?= $(TB_DIR)/fakeram130_128x64.sv
CELLGATE ?= $(TB_DIR)/cells_clkgate_sim.v

SIM ?= verilator
TOPLEVEL_LANG := verilog
TOPLEVEL ?= systolic_top
COCOTB_TOPLEVEL := $(TOPLEVEL)
MODULE ?= test_$(TOPLEVEL)
COCOTB_TEST_MODULES := $(MODULE)

RTL_SOURCES := $(wildcard $(RTL)/*.sv)
VERILOG_SOURCES = $(CELLGATE) $(wildcard $(RTL)/*.sv) $(TB_DIR)/fakeram130_128x64.sv

SIM_BUILD = $(TB_DIR)/sim_build_$(TOPLEVEL)

EXTRA_ARGS += -Wall
EXTRA_ARGS += $(TB_DIR)/lint.vlt

export PYTHONPATH := $(TB_DIR)$(if $(PYTHONPATH),:$(PYTHONPATH))

ifeq ($(strip $(shell command -v cocotb-config 2>/dev/null)),)
  $(error cocotb-config not found in PATH. Activate the environment with Cocotb installed)
endif
ifeq ($(strip $(shell command -v $(SIM) 2>/dev/null)),)
  $(error Simulator '$(SIM)' not found in PATH. Install/activate Verilator or choose SIM=icarus)
endif
ifeq ($(strip $(RTL_SOURCES)),)
  $(error No RTL .sv files found in RTL='$(RTL)'. Set RTL=/path/to/rtl)
endif
ifeq ($(wildcard $(CELLGATE)),)
  $(error Clock-gate simulation model not found: '$(CELLGATE)')
endif
ifeq ($(wildcard $(FAKERAM)),)
  $(error Fake RAM source not found: '$(FAKERAM)')
endif
ifeq ($(wildcard $(TB_DIR)/lint.vlt),)
  $(error Verilator lint config not found: '$(TB_DIR)/lint.vlt')
endif

COCOTB_CONFIG := $(shell command -v cocotb-config 2>/dev/null)
COCOTB_MAKEFILES := $(shell $(COCOTB_CONFIG) --makefiles 2>/dev/null)
ifeq ($(strip $(COCOTB_MAKEFILES)),)
  $(error 'cocotb-config --makefiles' failed. Check the active Cocotb installation)
endif

include $(COCOTB_MAKEFILES)/Makefile.sim

.PHONY: list-sources
list-sources:
	@printf 'ROOT=%s\nTB_DIR=%s\nRTL=%s\nFAKERAM=%s\nCELLGATE=%s\n' '$(ROOT)' '$(TB_DIR)' '$(RTL)' '$(FAKERAM)' '$(CELLGATE)'
	@printf '%s\n' 'Verilog sources:' $(VERILOG_SOURCES)
