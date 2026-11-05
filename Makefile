.DEFAULT_GOAL := help
.SUFFIXES:
MAKEFLAGS += --no-builtin-rules

ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
RTL := $(ROOT)/rtl
TB := $(ROOT)/tb

CSR_RDL    := $(ROOT)/csr/my_csr.rdl
CSR_OUT    := $(RTL)/csr_generated
CSR_HEADER := $(CSR_OUT)/my_csr.h

RTL_FILELIST := $(RTL)/files.f
SIM_FILELIST := $(TB)/files_sim.f

rtl_src = $(addprefix $(RTL)/,$(filter-out cells_clkgate.v,$(shell \
	sed -e 's/[[:space:]]*#.*$$//' \
	    -e '/^[[:space:]]*$$/d' "$(RTL_FILELIST)")))

sim_src = $(addprefix $(TB)/,$(shell \
	sed -e 's/[[:space:]]*#.*$$//' \
	    -e '/^[[:space:]]*$$/d' "$(SIM_FILELIST)"))

export ROOT_DIR := $(ROOT)

PYTHON  ?= python3
PEAKRDL ?= peakrdl


ORFS_FLOW ?= $(HOME)/eda/orfs-nix/OpenROAD-flow-scripts/flow

RUN_TAG  ?= default
WORK_HOME ?= $(ROOT)/orfs-out/$(CONFIG_NAME)/$(RUN_TAG)

# make flow TECH=sky130
# make flow TECH=nangate45

TECH ?= sky130
override TECH := $(patsubst sky130hd,sky130,$(TECH))

ifeq ($(TECH),sky130)
    PLATFORM_MK := sky130hd
else ifeq ($(TECH),nangate45)
    PLATFORM_MK := nangate45
else
    $(error Unsupported TECH='$(TECH)'. Use TECH=sky130 or TECH=nangate45)
endif

NODE := $(TECH)

DESIGN_CONFIG ?= design-configs/$(PLATFORM_MK).mk

# Resolve relative DESIGN_CONFIG paths from the project root.
ifeq ($(filter /%,$(DESIGN_CONFIG)),)
    CFG := $(abspath $(ROOT)/$(DESIGN_CONFIG))
else
    CFG := $(abspath $(DESIGN_CONFIG))
endif

CONFIG_NAME := $(basename $(notdir $(CFG)))
FAKERAM_DIR := $(ROOT)/fakeram/$(TECH)
MEM_MACROS  := sram_sp_64x64 sram_sp_64x256

CACTI_BUILD_DIR ?= $(HOME)/eda/bsg_fakeram/tools/cacti

# ORFS invocation.
ORFS = $(MAKE) --no-print-directory -C "$(ORFS_FLOW)" \
    DESIGN_CONFIG="$(CFG)" \
    WORK_HOME="$(WORK_HOME)"

.PHONY: help

help:
	@printf '%s\n' \
	    'Project:' \
	    '  make lint' \
	    '  make test' \
	    '  make csr' \
	    '  make clean | distclean' \
	    '' \
	    'Simulation:' \
	    '  make test' \
	    '  make -C tb test-all' \
	    '  make -C tb TOPLEVEL=pe MODULE=test_pe' \
	    '  make -C tb TOPLEVEL=sram_wrap MODULE=test_sram_wrap SRAM_DEPTH=256 SRAM_ADDR_W=8' \
	    '  make -C tb TOPLEVEL=mem_arb_tb_top MODULE=test_mem_arb' \
	    '' \
	    'CSR generation:' \
	    '  RTL:    rtl/csr_generated/' \
	    '  Header: rtl/csr_generated/my_csr.h' \
	    '' \
	    'Physical design:' \
	    '  make fakeram TECH=sky130|nangate45' \
	    '  make flow TECH=sky130|nangate45' \
	    '  make flow-all' \
	    '' \
	    'Run variants:' \
	    '  make flow RUN_TAG=baseline' \
	    '  make flow RUN_TAG=timing_opt' \
	    '  make flow RUN_TAG=area_opt' \
	    '  make flow RUN_TAG=low_power' \
	    '' \
	    'Individual ORFS stages:' \
	    '  make synth|floorplan|place|cts|route|finish' \
	    '' \
	    'Timing analysis:' \
	    '  make sta [STAGE=synth|floorplan|place|cts|route|final]' \
	    '  make sta-shell STAGE=cts' \
	    '  make sta-all' \
	    '  make presta | presta-shell' \
	    '' \
	    'Output:' \
	    '  WORK_HOME=/path/to/run' \
	    '  RUN_TAG=baseline'

.PHONY: check-design-config check-fakeram

check-design-config:
	@test -f "$(CFG)" || { \
	    echo "ERROR: DESIGN_CONFIG not found: $(CFG)"; \
	    exit 1; \
	}

check-fakeram:
	@set -e; for m in $(MEM_MACROS); do \
	    lef="$(FAKERAM_DIR)/$$m/$$m.lef"; \
	    if [ ! -f "$$lef" ]; then \
	        echo "ERROR: SRAM macro not found: $$lef"; \
	        echo "Run: make fakeram TECH=$(TECH)"; \
	        exit 1; \
	    fi; \
	done

.PHONY: lint

lint:
	verilator --lint-only -Wall -Wno-fatal \
	    $(rtl_src) \
	    $(sim_src) \
	    --top-module systolic_array

.PHONY: test

test:
	$(MAKE) --no-print-directory -C "$(TB)" test-all

.PHONY: csr

csr:
	@test -f "$(CSR_RDL)" || { \
	    echo "ERROR: CSR description not found: $(CSR_RDL)"; \
	    exit 1; \
	}
	@mkdir -p "$(CSR_OUT)"
	$(PEAKRDL) regblock "$(CSR_RDL)" \
	    -o "$(CSR_OUT)" \
	    --cpuif apb4-flat \
	    --default-reset arst_n
	$(PEAKRDL) c-header "$(CSR_RDL)" \
	    -o "$(CSR_HEADER)"

.PHONY: fakeram fakeram-check

fakeram:
	@test -f "$(ROOT)/fakeram/$(TECH)_fakeram.cfg" || { \
	    echo "ERROR: Missing CACTI configuration:"; \
	    echo "       $(ROOT)/fakeram/$(TECH)_fakeram.cfg"; \
	    exit 1; \
	}
	cd "$(HOME)/eda/bsg_fakeram" && \
	    $(PYTHON) scripts/run.py \
	        "$(ROOT)/fakeram/$(TECH)_fakeram.cfg" \
	        --output_dir "$(FAKERAM_DIR)" \
	        --cacti_dir "$(CACTI_BUILD_DIR)"
ifeq ($(TECH),sky130)
	@set -e; for m in $(MEM_MACROS); do \
	    $(PYTHON) "$(ROOT)/scripts/fix_fakeram_lef.py" \
	        "$(FAKERAM_DIR)/$$m/$$m.lef"; \
	done
endif

fakeram-check: check-fakeram

.PHONY: flow flow-all

flow: check-design-config check-fakeram
	$(ORFS) finish

flow-all:
	$(MAKE) --no-print-directory flow TECH=sky130
	$(MAKE) --no-print-directory flow TECH=nangate45


.PHONY: synth floorplan place cts route finish

synth floorplan place cts route finish: check-design-config
	$(ORFS) $@

# Alternative ORFS target names.
.PHONY: orfs

orfs: check-design-config
	$(ORFS) finish

orfs-%: check-design-config
	$(ORFS) $*

STAGE ?= latest

MACRO_LIBS := $(wildcard $(FAKERAM_DIR)/*/*.lib)

STA_ENV = WORK_HOME="$(WORK_HOME)" \
          ORFS_FLOW="$(ORFS_FLOW)" \
          STAGE="$(STAGE)" \
          RUN_TAG="$(RUN_TAG)" \
          STA_MACRO_LIBS="$(MACRO_LIBS)"

ifeq ($(TECH),sky130)
    PRE_LIB := sky130_fd_sc_hd__tt_025C_1v80.lib
    PRE_DEF := OPENROAD_CLKGATE_SKY130
else
    PRE_LIB := NangateOpenCellLibrary_typical.lib
    PRE_DEF := OPENROAD_CLKGATE_NANGATE45
endif

PRE_ENV = TOP=systolic_top \
          USE_SLANG=1 \
          RTL_ROOT="$(RTL)" \
          RTL_FILELIST="$(RTL_FILELIST)" \
          RTL_FILES="$(RTL)/cells_clkgate.v" \
          DEFINES="$(PRE_DEF)" \
          LIBERTY="$(ORFS_FLOW)/platforms/$(PLATFORM_MK)/lib/$(PRE_LIB)" \
          MACRO_LIBS="$(MACRO_LIBS)" \
          SDC_FILE="$(ROOT)/constraints/constraints.sdc" \
          OUT_DIR="$(WORK_HOME)/reports/$(PLATFORM_MK)/pre_sta"

.PHONY: sta sta-shell sta-all presta presta-shell

sta: check-design-config
	$(STA_ENV) openroad -no_splash -exit "$(ROOT)/scripts/sta.tcl"

sta-shell: check-design-config
	$(STA_ENV) openroad -no_splash "$(ROOT)/scripts/sta.tcl"

sta-all:
	@set -e; \
	for s in synth floorplan place cts route final; do \
	    $(MAKE) --no-print-directory sta STAGE=$$s; \
	done

presta: check-design-config
	$(PRE_ENV) openroad -no_splash -exit "$(ROOT)/scripts/sta_pre.tcl"

presta-shell: check-design-config
	$(PRE_ENV) SKIP_SYNTH=1 openroad -no_splash "$(ROOT)/scripts/sta_pre.tcl"

.PHONY: clean distclean

clean:
	rm -rf \
	    "$(TB)"/sim_build_* \
	    "$(TB)"/results*.xml \
	    "$(TB)"/*.vcd \
	    "$(TB)"/*.fst \
	    "$(ROOT)/obj_dir" \
	    "$(ROOT)/results.xml" \
	    "$(ROOT)"/*.vcd \
	    "$(ROOT)"/*.fst
	@$(MAKE) --no-print-directory -C "$(TB)" -f "$(TB)/clean.mk"

distclean: clean
	find "$(ROOT)" -path "$(ROOT)/.venv" -prune -o \
	    -type d -name __pycache__ -prune -exec rm -rf {} +
	find "$(ROOT)" -path "$(ROOT)/.venv" -prune -o \
	    -type f -name '*.pyc' -delete
