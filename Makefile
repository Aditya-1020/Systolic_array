.DEFAULT_GOAL := help
.SUFFIXES:
MAKEFLAGS += --no-builtin-rules

ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
RTL := $(ROOT)/rtl
TB := $(ROOT)/tb
CSR_RDL := $(ROOT)/csr/my_csr.rdl
CSR_OUT := $(RTL)/csr

RTL_FILELIST := $(RTL)/files.f
SIM_FILELIST := $(TB)/files_sim.f

rtl_src = $(addprefix $(RTL)/,$(filter-out cells_clkgate.v,$(shell grep -vE '^\s*(#|$$)' $(RTL_FILELIST))))
sim_src = $(addprefix $(TB)/,$(shell grep -vE '^\s*(#|$$)' $(SIM_FILELIST)))

TESTS := pe array postproc systolic_core systolic_ctrl accel_top

# ORFS
PLATFORM ?= sky130hd
DESIGN ?= systolic
ORFS_FLOW ?= $(HOME)/eda/orfs-nix/OpenROAD-flow-scripts/flow
WORK_HOME ?= $(ROOT)/orfs-out
CFG := $(ROOT)/design-configs/$(DESIGN).mk
export ROOT_DIR := $(ROOT)
export PLATFORM
ORFS = $(MAKE) --no-print-directory -C "$(ORFS_FLOW)" \
       DESIGN_CONFIG="$(CFG)" WORK_HOME="$(WORK_HOME)" PLATFORM="$(PLATFORM)"

.PHONY: help lint test csr clean distclean \
        fakeram orfs orfs-% synth floorplan place cts route finish

help:
	@printf '%s\n' \
	  'make lint|test|csr|clean' \
	  'make fakeram - generate macros into fakeram/ (needs bsg_fakeram)' \
	  'make synth|… PLATFORM=sky130hd|nangate45  - ORFS (sets OPENROAD_CLKGATE_*)' \
	  'make -C tb TOPLEVEL=accel_top - RTL top TB' \
	  'make -C tb TOPLEVEL=accel_top STAGE=synth|place|final - same TB on ORFS netlist' \
	  'make -C tb TOPLEVEL=accel_top NETLIST=/path/to.v - explicit netlist' \
	  'Sim/lint use tb/helper/cells_clkgate_sim.v (no tech define).'

lint:
	# Behavioral clkgate model; synth uses rtl/cells_clkgate.v + VERILOG_DEFINES
	verilator --lint-only -Wall -Wno-fatal \
	  $(rtl_src) $(sim_src) $(TB)/lint.vlt \
	  --top-module accel_top

test:
	@set -e; for t in $(TESTS); do \
	  echo "==== TEST $$t ===="; \
	  $(MAKE) -C $(TB) TOPLEVEL=$$t MODULE=test_$$t; \
	done

csr:
	peakrdl regblock $(CSR_RDL) -o $(CSR_OUT) --cpuif apb4-flat --default-reset rst
	-peakrdl cheader $(CSR_RDL) -o $(CSR_OUT)

fakeram:
	@test -n "$$CACTI_BUILD_DIR" || export CACTI_BUILD_DIR=$(HOME)/eda/bsg_fakeram/tools/cacti; \
	cd $(HOME)/eda/bsg_fakeram && \
	  python3 scripts/run.py $(ROOT)/fakeram/sky130_fakeram.cfg \
	    --output_dir $(ROOT)/fakeram --cacti_dir $${CACTI_BUILD_DIR}

synth floorplan place cts route finish:
	$(ORFS) $@

orfs:
	$(ORFS) finish

orfs-%:
	$(ORFS) $*

clean:
	rm -rf $(TB)/sim_build_* $(TB)/results.xml $(TB)/*.vcd $(TB)/*.fst \
	  $(ROOT)/obj_dir $(ROOT)/results.xml $(ROOT)/*.vcd $(ROOT)/*.fst
	@$(MAKE) -C $(TB) -f $(TB)/clean.mk TOPLEVEL=pe >/dev/null 2>&1 || true

distclean: clean
	find $(ROOT) -type d -name __pycache__ -not -path '*/.venv/*' -prune -exec rm -rf {} +
	find $(ROOT) -type f -name '*.pyc' -not -path '*/.venv/*' -delete
