# Netlist / ORFS stage selection (accel_top)
#   STAGE=rtl                         - behavioral RTL (default)
#   STAGE=synth|floorplan|place|cts|route|final
#   NETLIST=/path/to/foo.v            - explicit netlist (overrides STAGE path)
#   PLATFORM, WORK_HOME, FLOW_VARIANT, DESIGN_NICKNAME - ORFS results lookup
# Examples:
#   make TOPLEVEL=accel_top
#   make TOPLEVEL=accel_top STAGE=synth
#   make TOPLEVEL=accel_top STAGE=place
#   make TOPLEVEL=accel_top NETLIST=/abs/path/6_final.v

.DEFAULT_GOAL := sim

ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)
TB_DIR := $(ROOT)/tb
HELPER := $(TB_DIR)/helper
RTL := $(ROOT)/rtl

TOPLEVEL ?= systolic_core
MODULE ?= test_$(TOPLEVEL)
SIM ?= verilator
PE_RTL ?= $(RTL)/pe.sv


STAGE ?= rtl
PLATFORM ?= sky130hd
WORK_HOME ?= $(ROOT)/orfs-out
DESIGN_NICKNAME ?= sys
FLOW_VARIANT ?= base
RESULTS_DIR ?= $(WORK_HOME)/results/$(PLATFORM)/$(DESIGN_NICKNAME)/$(FLOW_VARIANT)

ORFS_FLOW ?= $(HOME)/eda/orfs-nix/OpenROAD-flow-scripts/flow
SKY130_VERILOG ?= $(HOME)/eda/.volare/sky130A/libs.ref/sky130_fd_sc_hd/verilog

# Map STAGE -> default netlist under RESULTS_DIR (ORFS naming).
# Intermediate odb stages need `<odb>.v` generated via ORFS `make <odb>.v`.
ifeq ($(STAGE),rtl)
NETLIST_DEFAULT :=
else ifeq ($(STAGE),synth)
NETLIST_DEFAULT := $(RESULTS_DIR)/1_2_yosys.v
else ifeq ($(STAGE),yosys)
NETLIST_DEFAULT := $(RESULTS_DIR)/1_2_yosys.v
else ifeq ($(STAGE),floorplan)
NETLIST_DEFAULT := $(RESULTS_DIR)/2_floorplan.odb.v
else ifeq ($(STAGE),place)
NETLIST_DEFAULT := $(RESULTS_DIR)/3_place.odb.v
else ifeq ($(STAGE),cts)
NETLIST_DEFAULT := $(RESULTS_DIR)/4_cts.odb.v
else ifeq ($(STAGE),route)
NETLIST_DEFAULT := $(RESULTS_DIR)/5_route.odb.v
else ifeq ($(STAGE),final)
NETLIST_DEFAULT := $(RESULTS_DIR)/6_final.v
else
$(error Unknown STAGE='$(STAGE)'; use rtl|synth|floorplan|place|cts|route|final)
endif

NETLIST ?= $(NETLIST_DEFAULT)
NETLIST_MODE := $(if $(filter-out rtl,$(STAGE)),1,$(if $(NETLIST),1,0))

COCOTB_TOPLEVEL := $(TOPLEVEL)
COCOTB_TEST_MODULES := $(MODULE)
SIM_BUILD := $(TB_DIR)/sim_build_$(TOPLEVEL)$(if $(filter-out rtl,$(STAGE)),_$(STAGE),)
EXTRA_ARGS += -Wall --trace --trace-structs

RTL_FILELIST := $(RTL)/files.f
SIM_FILELIST := $(TB_DIR)/files_sim.f

# Expand filelists; paths inside each .f are relative to that .f's directory.
rtl_list = $(addprefix $(RTL)/,$(filter-out cells_clkgate.v,$(shell grep -vE '^\s*(#|$$)' $(RTL_FILELIST))))
sim_list = $(addprefix $(TB_DIR)/,$(shell grep -vE '^\s*(#|$$)' $(SIM_FILELIST)))

# Behavioral SRAM models always needed (RTL + netlist blackboxes).
FAKERAM_SIM := \
	$(HELPER)/fakeram130_256x64.sv \
	$(HELPER)/fakeram130_512x64.sv \
	$(HELPER)/fakeram130_128x64.sv

ifeq ($(TOPLEVEL),pe)
VERILOG_SOURCES := $(PE_RTL)
else ifeq ($(NETLIST_MODE),1)
ifeq ($(wildcard $(NETLIST)),)
$(error Netlist not found: $(NETLIST). Run the ORFS stage or pass NETLIST=...)
endif
# Gate-level / synth netlist + cell models + SRAM behavioral stand-ins.
# Do not compile RTL (would collide with the netlist module).
CELL_VERILOG :=
ifeq ($(PLATFORM),sky130hd)
CELL_VERILOG := $(SKY130_VERILOG)/primitives.v $(SKY130_VERILOG)/sky130_fd_sc_hd.v
COMPILE_ARGS += -DFUNCTIONAL -DUNIT_DELAY
# Verilator: treat specify/UDP noise as non-fatal for PDK models.
EXTRA_ARGS += -Wno-fatal -Wno-TIMESCALEMOD -Wno-STMTDLY -Wno-LITENDIAN
endif
VERILOG_SOURCES := $(NETLIST) $(CELL_VERILOG) $(FAKERAM_SIM)
else
VERILOG_SOURCES := $(rtl_list) $(sim_list)
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
else ifneq ($(NETLIST_MODE),1)
ifeq ($(wildcard $(RTL_FILELIST)),)
$(error RTL filelist not found: $(RTL_FILELIST))
endif
ifeq ($(wildcard $(SIM_FILELIST)),)
$(error Sim filelist not found: $(SIM_FILELIST))
endif
endif

COCOTB_MAKEFILES := $(shell cocotb-config --makefiles)
ifeq ($(strip $(COCOTB_MAKEFILES)),)
$(error Failed to locate Cocotb Makefiles)
endif

include $(COCOTB_MAKEFILES)/Makefile.sim

.PHONY: clean-up list-sources dump-netlist help-netlist

help-netlist:
	@printf '%s\n' \
	  'RTL:     make -C tb TOPLEVEL=accel_top' \
	  'Synth:   make -C tb TOPLEVEL=accel_top STAGE=synth' \
	  'Place:   make -C tb TOPLEVEL=accel_top STAGE=place' \
	  'Final:   make -C tb TOPLEVEL=accel_top STAGE=final' \
	  'Custom:  make -C tb TOPLEVEL=accel_top NETLIST=/path/to/netlist.v' \
	  'Dump .v: make -C tb dump-netlist STAGE=place   # via ORFS write_verilog'

# Generate <stage>.odb.v from ORFS results when missing (floorplan..route).
dump-netlist:
	@odb="$(NETLIST)"; \
	case "$(STAGE)" in \
	  floorplan) odb="$(RESULTS_DIR)/2_floorplan.odb" ;; \
	  place)     odb="$(RESULTS_DIR)/3_place.odb" ;; \
	  cts)       odb="$(RESULTS_DIR)/4_cts.odb" ;; \
	  route)     odb="$(RESULTS_DIR)/5_route.odb" ;; \
	  final)     odb="$(RESULTS_DIR)/6_final.odb" ;; \
	  synth|yosys|rtl) echo "STAGE=$(STAGE) needs no odb dump"; exit 0 ;; \
	  *) echo "dump-netlist: unsupported STAGE=$(STAGE)"; exit 1 ;; \
	esac; \
	test -f "$$odb" || { echo "Missing $$odb"; exit 1; }; \
	$(MAKE) --no-print-directory -C "$(ORFS_FLOW)" \
	  DESIGN_CONFIG="$(ROOT)/design-configs/systolic.mk" \
	  WORK_HOME="$(WORK_HOME)" PLATFORM="$(PLATFORM)" \
	  "$$(basename $$odb).v"

clean-up:
	$(MAKE) -f $(TB_DIR)/clean.mk TOPLEVEL=$(TOPLEVEL)
	rm -rf *.vcd *.fst results.xml

list-sources:
	@printf 'TOPLEVEL=%s MODULE=%s SIM=%s STAGE=%s\n' '$(TOPLEVEL)' '$(MODULE)' '$(SIM)' '$(STAGE)'
	@printf 'NETLIST=%s\n' '$(NETLIST)'
	@printf '%s\n' $(VERILOG_SOURCES)
