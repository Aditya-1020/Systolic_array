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

# Number of parallel C++ compiele jobs
JOBS ?= 4

# Enable waveform tracing:
# RTL default = 1
# Gate-level default = 0
ifeq ($(origin TRACE),undefined)
    ifdef NETLIST
        TRACE := 0
    else
        TRACE := 1
    endif
endif

read_filelist = $(shell sed -e 's/[[:space:]]*#.*//' -e '/^[[:space:]]*$$/d' $(1))

# Gate-level regression
ifdef NETLIST

TOPLEVEL := sys_top
MODULE := test_sys_top_apb

COCOTB_TOPLEVEL := $(TOPLEVEL)
COCOTB_TEST_MODULES := $(MODULE)

GL_TAG ?= gl

VERILOG_SOURCES := \
    $(TB_DIR)/models/sky130_dlclkp_sim.v \
    $(NETLIST) \
    $(CELL_LIBS) \
    $(TB_DIR)/models/fakeram_sim.v

HASH := \#
GL_DELAY ?= 0
COMPILE_ARGS += \
    --timing \
    -Wno-fatal \
    -Wno-PINMISSING \
    -DFUNCTIONAL \
    --timescale 1ns/1ps \
    "-DUNIT_DELAY=$(if $(filter-out 0,$(GL_DELAY)),$(HASH)$(GL_DELAY),)" \
    -DSKY130_FD_SC_HD__DLCLKP_1_V

COMPILE_ARGS += -CFLAGS "-O0 -g0"

SIM_BUILD := $(TB_DIR)/sim_build_gl_$(GL_TAG)
COCOTB_RESULTS_FILE := $(TB_DIR)/results_gl_$(GL_TAG).xml

# RTL regression
else

rtl_sources := $(addprefix $(RTL_DIR)/,$(call read_filelist,$(RTL_DIR)/files.f))
sim_sources := $(addprefix $(TB_DIR)/,$(call read_filelist,$(TB_DIR)/files_sim.f))

# Use behavioral clock-gating model from simulation filelist.
rtl_sources := $(filter-out $(RTL_DIR)/cells_clkgate.v,$(rtl_sources))

tb_top_src := $(filter-out $(sim_sources),$(wildcard $(TB_DIR)/$(TOPLEVEL).sv))

VERILOG_SOURCES := $(rtl_sources) $(sim_sources) $(tb_top_src)

COMPILE_ARGS += --timing -Wno-fatal

# SRAM parameters
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
endif

# wave tracing
ifeq ($(TRACE),1)
    EXTRA_ARGS += --trace
endif

# Parallel compilation
# Propagate parallel-job config
MAKEFLAGS += -j$(JOBS)

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
		'make TOPLEVEL=sys_top MODULE=test_sys_top_apb' \
		'make TOPLEVEL=sram_wrap MODULE=test_sram_wrap SRAM_DEPTH=64 SRAM_ADDR_W=6' \
		'make TOPLEVEL=sram_wrap MODULE=test_sram_wrap SRAM_DEPTH=256 SRAM_ADDR_W=8' \
		'make TOPLEVEL=mem_arb_tb_top MODULE=test_mem_arb' \
		'' \
		'Performance options:' \
		'make sim JOBS=4 TRACE=0' \
		'make sim JOBS=8 TRACE=1' \
		'' \
		'Gate-level:' \
		'make sim NETLIST=/path/to/1_2_yosys.v CELL_LIBS="prim.v cells.v" GL_TAG=sky130_base_synth [GL_DELAY=0.01]'

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
		echo '========== SYS_TOP APB =========='; \
		$(MAKE) --no-print-directory TOPLEVEL=sys_top MODULE=test_sys_top_apb sim
