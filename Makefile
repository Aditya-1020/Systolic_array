.DEFAULT_GOAL := help
.SUFFIXES:
.DELETE_ON_ERROR:
MAKEFLAGS += --no-builtin-rules

ROOT_DIR      := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
DESIGN        ?= systolic
PLATFORM      ?= sky130hd
FLOW_VARIANT  ?=
STOP          ?= finish
ORFS_FLOW     ?= $(HOME)/eda/orfs-nix/OpenROAD-flow-scripts/flow
WORK_HOME     ?= $(ROOT_DIR)/orfs-out
TOP           ?= 10
CORNER        ?= tt_025C_1v80

CFG := $(abspath $(if $(CONFIG_MK),$(CONFIG_MK),$(ROOT_DIR)/design-configs/$(DESIGN).mk))
export ROOT_DIR PLATFORM

ifeq ($(wildcard $(CFG)),)
$(error Config not found: $(CFG). Set DESIGN=<name> or CONFIG_MK=<path>)
endif
include $(CFG)

# Core-cell timing library and extraction rules.
ifeq ($(PLATFORM),sky130hd)
  PLATFORM_LIB := $(ORFS_FLOW)/platforms/sky130hd/lib/sky130_fd_sc_hd__$(CORNER).lib
else ifeq ($(PLATFORM),nangate45)
  PLATFORM_LIB := $(ORFS_FLOW)/platforms/nangate45/lib/NangateOpenCellLibrary_typical.lib
else
  $(error Unsupported PLATFORM '$(PLATFORM)'; use sky130hd or nangate45)
endif
PLATFORM_RC_TCL := $(ORFS_FLOW)/platforms/$(PLATFORM)/setRC.tcl
export PLATFORM_LIB

# Keep the empty variant default to preserve the current orfs-out/<stage>/<platform>/<design>
# directory layout. Set VARIANT=base explicitly only when you want a separate run.
RESULTS := $(WORK_HOME)/results/$(PLATFORM)/$(DESIGN_NICKNAME)/$(FLOW_VARIANT)
REPORTS := $(WORK_HOME)/reports/$(PLATFORM)/$(DESIGN_NICKNAME)/$(FLOW_VARIANT)
LOGS    := $(WORK_HOME)/logs/$(PLATFORM)/$(DESIGN_NICKNAME)/$(FLOW_VARIANT)
OBJECTS := $(WORK_HOME)/objects/$(PLATFORM)/$(DESIGN_NICKNAME)/$(FLOW_VARIANT)

# Forward only supported configuration hooks, with paths normalized to absolute paths.
HOOKS := PRE_SYNTH_TCL POST_SYNTH_TCL PRE_FLOORPLAN_TCL POST_FLOORPLAN_TCL \
         PRE_MACRO_PLACE_TCL POST_MACRO_PLACE_TCL POST_GLOBAL_PLACE_TCL \
         POST_DETAIL_PLACE_TCL PRE_CTS_TCL POST_CTS_TCL PRE_GLOBAL_ROUTE_TCL \
         POST_GLOBAL_ROUTE_TCL POST_DETAIL_ROUTE_TCL PRE_FINAL_REPORT_TCL POST_FINAL_REPORT_TCL
HOOK_ARGS = $(foreach v,$(HOOKS),$(if $($(v)),$(v)=$(abspath $($(v)))))
ORFS = $(MAKE) --no-print-directory -C "$(ORFS_FLOW)" \
       DESIGN_CONFIG="$(CFG)" WORK_HOME="$(WORK_HOME)" \
       FLOW_VARIANT="$(FLOW_VARIANT)" PLATFORM="$(PLATFORM)" $(HOOK_ARGS)

# Small helpers.
empty :=
space := $(empty) $(empty)
need-file = @test -f "$(1)" || { echo "ERROR: missing file: $(1)" >&2; exit 1; }

.PHONY: help paths check-config synth synth-report floorplan place cts grt route finish flow orfs orfs-% \
        presta presta-shell sta sta-all viol viol-summary sta-shell clean-pre clean-orfs

help: ## List common commands
	@printf '%s\n' \
	  'Core:       make synth | synth-report | floorplan | place | cts | grt | route | finish' \
	  'Timing:     make sta [STAGE=synth|final|<ODB-stem>] | viol | sta-all | sta-shell' \
	  'Pre-layout: make presta | presta-shell' \
	  'Utilities:  make paths | check-config | clean-pre | clean-orfs VARIANT=<explicit>' \
	  '' \
	  'Overrides: DESIGN=$(DESIGN) PLATFORM=$(PLATFORM) VARIANT=$(if $(strip $(VARIANT)),$(VARIANT),<empty/current-layout>) STOP=$(STOP)' \
	  'Use VARIANT=base for a separate output tree; it will not reuse the current empty-variant outputs.'

paths: ## Show resolved configuration and output paths
	@printf '%-16s %s\n' \
	  ROOT_DIR "$(ROOT_DIR)" \
	  ORFS_FLOW "$(ORFS_FLOW)" \
	  CFG "$(CFG)" \
	  DESIGN_NAME "$(DESIGN_NAME)" \
	  DESIGN_NICKNAME "$(DESIGN_NICKNAME)" \
	  PLATFORM "$(PLATFORM)" \
	  PLATFORM_LIB "$(PLATFORM_LIB)" \
	  SDC_FILE "$(SDC_FILE)" \
	  RESULTS "$(RESULTS)" \
	  REPORTS "$(REPORTS)" \
	  LOGS "$(LOGS)" \
	  PRE_DIR "$(PRE_DIR)"

check-config: ## Check ORFS, SDC, RTL and macro-library inputs
	$(call need-file,$(ORFS_FLOW)/Makefile)
	$(call need-file,$(PLATFORM_LIB))
	$(call need-file,$(PLATFORM_RC_TCL))
	$(call need-file,$(SDC_FILE))
	@set -eu; for f in $(VERILOG_FILES); do \
	  test -f "$$f" || { echo "ERROR: missing RTL: $$f" >&2; exit 1; }; \
	done
	@if [ -n "$(strip $(ADDITIONAL_LEFS))" ]; then \
	  for f in $(ADDITIONAL_LEFS); do test -f "$$f" || exit 1; done; \
	else echo "ERROR: no macro LEF found (ADDITIONAL_LEFS is empty)" >&2; exit 1; fi
	@if [ -n "$(strip $(ADDITIONAL_LIBS))" ]; then \
	  for f in $(ADDITIONAL_LIBS); do test -f "$$f" || exit 1; done; \
	else echo "ERROR: no macro Liberty found (ADDITIONAL_LIBS is empty)" >&2; exit 1; fi
	@echo "Configuration files exist."

# ORFS stages. These are short aliases; ORFS owns the stage dependency graph.
synth: ## Synthesize RTL only
	$(ORFS) synth

synth-report: ## Print ORFS synthesis report files
	@find "$(REPORTS)" -type f \( -iname '*synth*' -o -iname '*stat*' \) -print 2>/dev/null | sort
	@find "$(REPORTS)" -type f \( -iname '*synth*' -o -iname '*stat*' \) -exec sh -c 'for f do echo; echo "===== $$f ====="; cat "$$f"; done' sh {} + 2>/dev/null

floorplan place cts grt route finish:
	$(ORFS) $@

flow: ## Run ORFS through STOP=<synth|floorplan|place|cts|grt|route|finish>
	$(ORFS) $(STOP)

orfs: ## Run ORFS default target
	$(ORFS)

orfs-%: ## Run an ORFS target directly, e.g. make orfs-synth
	$(ORFS) $*

# Standalone Yosys + OpenSTA estimate (not the ORFS synthesized design).
PRE_ENV = TOP="$(DESIGN_NAME)" LIBERTY="$(PLATFORM_LIB)" SDC_FILE="$(SDC_FILE)" \
          OUT_DIR="$(PRE_DIR)" RTL_FILES="$(or $(RTL_FILES),$(VERILOG_FILES))"

presta: ## Synthesize RTL separately with Yosys and run pre-layout OpenSTA
	$(PRE_ENV) sta -no_splash -exit "$(ROOT_DIR)/scripts/sta_pre.tcl"

presta-shell: ## Reopen standalone pre-layout STA using its saved netlist
	@test -f "$(PRE_DIR)/netlist.v" || { echo "Run 'make presta' first." >&2; exit 1; }
	$(PRE_ENV) SKIP_SYNTH=1 sta -no_splash "$(ROOT_DIR)/scripts/sta_pre.tcl"

# OpenROAD STA against an ORFS ODB. STAGE accepts synth, final, or an ODB stem.
STAGE ?= synth
STA_STAGE = $(if $(filter synth,$(STAGE)),1_synth,$(if $(filter final,$(STAGE)),6_final,$(STAGE)))
STA_ODB   = $(RESULTS)/$(STA_STAGE).odb
STA_DIR   = $(REPORTS)/sta/$(STA_STAGE)
STA_MACRO_LIBS = $(subst $(space),:,$(strip $(ADDITIONAL_LIBS)))
STA_ENV = STA_ODB="$(STA_ODB)" STA_RESULTS_DIR="$(RESULTS)" \
          STA_SDC_FALLBACK="$(SDC_FILE)" STA_LIBERTY="$(PLATFORM_LIB)" \
          STA_MACRO_LIBS="$(STA_MACRO_LIBS)" STA_RC_TCL="$(PLATFORM_RC_TCL)" \
          STA_REPORT_DIR="$(STA_DIR)"

STA_ALL := 1_synth 2_1_floorplan 2_2_floorplan_macro 2_3_floorplan_tapcell 2_4_floorplan_pdn \
           3_1_place_gp_skip_io 3_2_place_iop 3_3_place_gp 3_4_place_resized 3_5_place_dp \
           4_1_cts 5_1_grt 5_2_route 5_3_fillcell 6_1_fill 6_final

sta: ## Generate post-ORFS STA reports for STAGE
	$(call need-file,$(STA_ODB))
	$(call need-file,$(PLATFORM_LIB))
	$(call need-file,$(PLATFORM_RC_TCL))
	$(STA_ENV) openroad -no_splash -exit "$(ROOT_DIR)/scripts/sta.tcl"

sta-all: ## Run STA on each stage with an existing ODB
	@set -e; for s in $(STA_ALL); do \
	  if [ -f "$(RESULTS)/$$s.odb" ]; then \
	    echo; echo "===== STA: $$s ====="; \
	    $(MAKE) --no-print-directory sta STAGE=$$s; \
	  fi; \
	done

viol: sta ## Generate STA reports and print clustered violations
	@$(MAKE) --no-print-directory viol-summary STAGE="$(STAGE)"

viol-summary: ## Print the existing STA summary and cluster violations
	$(call need-file,$(STA_DIR)/summary.rpt)
	@cat "$(STA_DIR)/summary.rpt"
	@awk -v top="$(TOP)" -f "$(ROOT_DIR)/scripts/cluster.awk" \
	  "$(STA_DIR)/setup_violations.rpt" \
	  "$(STA_DIR)/hold_violations.rpt" \
	  "$(STA_DIR)/electrical_violations.rpt"
	@echo; echo "Worst-path details: $(STA_DIR)/{setup,hold}_worst_paths.rpt"

sta-shell: ## Open interactive OpenROAD STA session for STAGE
	$(call need-file,$(STA_ODB))
	$(STA_ENV) openroad -no_splash "$(ROOT_DIR)/scripts/sta.tcl"

clean-pre: ## Remove standalone pre-layout STA outputs only
	@test "$(PRE_DIR)" = "$(WORK_HOME)/pre/$(DESIGN_NICKNAME)" || exit 1
	rm -rf -- "$(PRE_DIR)"

clean-orfs: ## Remove one explicitly named ORFS variant (requires VARIANT=...)
	@test -n "$(strip $(VARIANT))" || { \
	  echo "Refusing to clean: set VARIANT explicitly so other runs are not deleted." >&2; exit 1; }
	@test "$(WORK_HOME)" != "/" && test -n "$(DESIGN_NICKNAME)" || exit 1
	rm -rf -- "$(LOGS)" "$(OBJECTS)" "$(REPORTS)" "$(RESULTS)"
	@echo "Removed ORFS outputs for $(PLATFORM)/$(DESIGN_NICKNAME)/$(VARIANT)."

