# Cocotb 2.x + Verilator unit-test entry point.
.DEFAULT_GOAL := sim

TOPLEVEL_LANG := verilog
SIM ?= verilator
TOPLEVEL ?= systolic_array
MODULE ?= test_systolic_array
COCOTB_TOPLEVEL := $(TOPLEVEL)
COCOTB_TEST_MODULES := $(MODULE)

ROOT := $(abspath ..)
TB_DIR := $(abspath .)
RTL_DIR := $(ROOT)/rtl

read_filelist = $(shell sed -e 's/[[:space:]]*#.*//' -e '/^[[:space:]]*$$/d' $(1))
rtl_sources := $(addprefix $(RTL_DIR)/,$(call read_filelist,$(RTL_DIR)/files.f))
sim_sources := $(addprefix $(TB_DIR)/,$(call read_filelist,$(TB_DIR)/files_sim.f))

rtl_sources := $(filter-out $(RTL_DIR)/cells_clkgate.v,$(rtl_sources))
VERILOG_SOURCES := $(rtl_sources) $(sim_sources)

COMPILE_ARGS += --timing -Wno-fatal --prefix Vtop
EXTRA_ARGS += --trace

SRAM_DEPTH ?= 64
SRAM_ADDR_W ?= 6
ifeq ($(TOPLEVEL),sram_wrap)
    COMPILE_ARGS += -GDEPTH=$(SRAM_DEPTH) -GADDR_W=$(SRAM_ADDR_W)
    SIM_BUILD := $(TB_DIR)/sim_build_sram_wrap_$(SRAM_DEPTH)x64
    COCOTB_RESULTS_FILE := $(TB_DIR)/results_sram_wrap_$(SRAM_DEPTH)x64.xml
else
    SIM_BUILD := $(TB_DIR)/sim_build_$(TOPLEVEL)
    COCOTB_RESULTS_FILE := $(TB_DIR)/results_$(TOPLEVEL).xml
endif

export PYTHONPATH := $(TB_DIR):$(TB_DIR)/helper$(if $(PYTHONPATH),:$(PYTHONPATH))

ifeq ($(shell command -v cocotb-config 2>/dev/null),)
$(error cocotb-config not found. Activate the project's virtual environment.)
endif

COCOTB_MAKEFILES := $(shell cocotb-config --makefiles)
include $(COCOTB_MAKEFILES)/Makefile.sim

.PHONY: help test test-all
help:
	@printf '%s\n' \
		'make test-all' \
		'make TOPLEVEL=pe MODULE=test_pe' \
		'make TOPLEVEL=round MODULE=test_round' \
		'make TOPLEVEL=relu MODULE=test_relu' \
		'make TOPLEVEL=postproc MODULE=test_postproc' \
		'make TOPLEVEL=systolic_array MODULE=test_systolic_array' \
		'make TOPLEVEL=sram_wrap MODULE=test_sram_wrap SRAM_DEPTH=64 SRAM_ADDR_W=6' \
		'make TOPLEVEL=sram_wrap MODULE=test_sram_wrap SRAM_DEPTH=256 SRAM_ADDR_W=8' \
		'make TOPLEVEL=mem_arb_tb_top MODULE=test_mem_arb'

test: test-all

test-all:
	@set -eu; \
		echo '========== PE =========='; \
		$(MAKE) --no-print-directory TOPLEVEL=pe MODULE=test_pe sim; \
		echo '========== ROUND =========='; \
		$(MAKE) --no-print-directory TOPLEVEL=round MODULE=test_round sim; \
		echo '========== RELU =========='; \
		$(MAKE) --no-print-directory TOPLEVEL=relu MODULE=test_relu sim; \
		echo '========== POSTPROC =========='; \
		$(MAKE) --no-print-directory TOPLEVEL=postproc MODULE=test_postproc sim; \
		echo '========== SYSTOLIC ARRAY =========='; \
		$(MAKE) --no-print-directory TOPLEVEL=systolic_array MODULE=test_systolic_array sim; \
		echo '========== SRAM WRAP 64x64 =========='; \
		$(MAKE) --no-print-directory TOPLEVEL=sram_wrap MODULE=test_sram_wrap SRAM_DEPTH=64 SRAM_ADDR_W=6 sim; \
		echo '========== SRAM WRAP 256x64 =========='; \
		$(MAKE) --no-print-directory TOPLEVEL=sram_wrap MODULE=test_sram_wrap SRAM_DEPTH=256 SRAM_ADDR_W=8 sim; \
		echo '========== MEMORY ARBITER =========='; \
		$(MAKE) --no-print-directory TOPLEVEL=mem_arb_tb_top MODULE=test_mem_arb sim; \
