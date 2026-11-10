.DEFAULT_GOAL := help
.SUFFIXES:
MAKEFLAGS += --no-builtin-rules

ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
ASICFLOW_REPO ?= $(abspath $(ROOT)/../orfs-custom-flow)
PYTHON ?= python3
PIP ?= $(PYTHON) -m pip
ASICFLOW := $(PYTHON) -m asicflow.flow
ORFSX ?= orfsx
PROJECT_CONFIG ?= $(ROOT)/asicflow.yaml
PEAKRDL ?= peakrdl

PLATFORM ?= sky130hd
ifeq ($(PLATFORM),sky130)
override PLATFORM := sky130hd
endif
RUN_TAG ?= base
FLOW_VARIANT ?= base
PLACEMENT ?= rtlmp
STAGE ?= synth
STA_STAGE ?= $(if $(filter synth,$(STAGE)),latest,$(STAGE))
METRICS_STAGE ?= $(if $(filter synth latest,$(STAGE)),place,$(STAGE))
QUERY_STAGE ?= $(if $(filter synth latest,$(STAGE)),place,$(STAGE))
ANALYSIS_STAGE ?= $(if $(filter synth,$(STAGE)),final,$(STAGE))
GUI_TARGET ?= final

ifeq ($(GUI_TARGET),synth)
GUI_ODB := 1_synth.odb
GUI_ORFS_TARGET := gui_synth
else ifeq ($(GUI_TARGET),floorplan)
GUI_ODB := 2_floorplan.odb
GUI_ORFS_TARGET := gui_floorplan
else ifeq ($(GUI_TARGET),place)
GUI_ODB := 3_place.odb
GUI_ORFS_TARGET := gui_place
else ifeq ($(GUI_TARGET),cts)
GUI_ODB := 4_cts.odb
GUI_ORFS_TARGET := gui_cts
else ifeq ($(GUI_TARGET),grt)
GUI_ODB := 5_1_grt.odb
GUI_ORFS_TARGET := gui_grt
else ifeq ($(GUI_TARGET),route)
GUI_ODB := 5_route.odb
GUI_ORFS_TARGET := gui_route
else ifeq ($(GUI_TARGET),final)
GUI_ODB := 6_final.odb
GUI_ORFS_TARGET := gui_final
else
$(error Unsupported GUI_TARGET "$(GUI_TARGET)"; choose synth, floorplan, place, cts, grt, route, or final)
endif

ORFS_FLOW ?= $(HOME)/eda/orfs-nix/OpenROAD-flow-scripts/flow
PDK_ROOT ?= $(HOME)/eda/.volare
DESIGN_CONFIG ?= design-configs/$(PLATFORM).mk
WORK_HOME ?= $(ROOT)/build/runs/$(PLATFORM)/systolic_array/$(RUN_TAG)
ASICFLOW_CONFIG_DIR ?= $(ROOT)/config
ASICFLOW_DESIGN_PROFILE ?= $(ROOT)/config/designs/systolic_array.yaml

export ROOT_DIR := $(ROOT)
export ORFS_FLOW PDK_ROOT PLATFORM RUN_TAG FLOW_VARIANT PLACEMENT
export DESIGN_CONFIG WORK_HOME ASICFLOW_CONFIG_DIR ASICFLOW_DESIGN_PROFILE

ifneq ($(strip $(CORE_UTILIZATION)),)
export CORE_UTILIZATION
endif
ifneq ($(strip $(CORE_ASPECT_RATIO)),)
export CORE_ASPECT_RATIO
endif
ifneq ($(strip $(CORE_MARGIN)),)
export CORE_MARGIN
endif

FLOW_ARGS = --platform "$(PLATFORM)" --run-tag "$(RUN_TAG)" --flow-variant "$(FLOW_VARIANT)" \
    --placement "$(PLACEMENT)" --design-config "$(DESIGN_CONFIG)" --work-home "$(WORK_HOME)" \
    --config-dir "$(ASICFLOW_CONFIG_DIR)" --design-profile "$(ASICFLOW_DESIGN_PROFILE)"

RESULTS_DIR := $(WORK_HOME)/results/$(PLATFORM)/systolic_array/$(FLOW_VARIANT)
RTL_FILELIST := $(ROOT)/rtl/files.f
RTL_SOURCES := $(addprefix $(ROOT)/rtl/,$(shell sed -e 's/[[:space:]]*#.*$$//' -e '/^[[:space:]]*$$/d' "$(RTL_FILELIST)")) $(ROOT)/rtl/cells_clkgate.v
TB := $(ROOT)/tb
CSR_RDL := $(ROOT)/csr/my_csr.rdl
CSR_OUT := $(ROOT)/rtl/csr_generated
FAKERAM_TECH := $(if $(filter sky130hd,$(PLATFORM)),sky130,$(PLATFORM))
FAKERAM_DIR := $(ROOT)/fakeram/$(FAKERAM_TECH)
FAKERAM_CONFIG := $(ROOT)/fakeram/$(FAKERAM_TECH)_fakeram.cfg

ifeq ($(PLATFORM),sky130hd)
CELL_LIBS ?= $(PDK_ROOT)/sky130A/libs.ref/sky130_fd_sc_hd/verilog/primitives.v $(PDK_ROOT)/sky130A/libs.ref/sky130_fd_sc_hd/verilog/sky130_fd_sc_hd.v
else ifeq ($(PLATFORM),nangate45)
CELL_LIBS ?= $(TB)/models/nangate45/NangateOpenCellLibrary.v
else
$(error Unsupported PLATFORM '$(PLATFORM)'; use sky130hd or nangate45)
endif

ifeq ($(STAGE),synth)
NETLIST_NAME := 1_2_yosys.v
else ifeq ($(STAGE),floorplan)
NETLIST_NAME := 2_floorplan.odb.v
else ifeq ($(STAGE),place)
NETLIST_NAME := 3_place.odb.v
else ifeq ($(STAGE),cts)
NETLIST_NAME := 4_cts.odb.v
else ifeq ($(STAGE),route)
NETLIST_NAME := 5_route.odb.v
else ifneq ($(filter $(STAGE),finish final),)
NETLIST_NAME := 6_final.v
else
NETLIST_NAME :=
endif
NETLIST := $(if $(strip $(NETLIST_NAME)),$(RESULTS_DIR)/$(NETLIST_NAME),)
FRONTEND_RTLIL ?= $(RESULTS_DIR)/1_1_yosys_canonicalize.rtlil
FRONTEND_V ?= $(RESULTS_DIR)/0_frontend.v

.PHONY: help install validate project-validate project-synth project-floorplan project-place project-cts project-route project-finish project-gui project-sta lint test csr fakeram synth floorplan place cts route finish flow gui gui-place sta-pvt sta-shell presta presta-both predict place-predict place-gen metrics metrics-all metrics-export sweep query report set-baseline summary regression analyze dataset compare-best netlist regress gl-regress regress-frontend gl-check clean distclean

help:
	@printf '%s\n' \
	  'ASICFlow / ORFS' \
	  '  make install [ASICFLOW_REPO=../orfs-custom-flow]' \
	  '  make validate PLATFORM=sky130hd|nangate45' \
	  '  make project-synth | project-place | project-sta | project-gui GUI_TARGET=place' \
	  '  make synth|floorplan|place|cts|route|finish|flow RUN_TAG=baseline' \
	  '  make sta-pvt STAGE=latest | make metrics STAGE=place' \
	  '  make metrics-all | make report | make query CATEGORY=timing' \
	  '  make sweep WHAT=util VALUES="40 50 60" SWEEP_EXECUTE=1' \
	  '  make gui GUI_TARGET=place | make place-gen SIDE=left NAME=left' \
	  '  make lint | test | regress | gl-check | gl-regress'

install:
	@test -f "$(ASICFLOW_REPO)/pyproject.toml" || { echo "ASICFlow repository not found: $(ASICFLOW_REPO)"; exit 1; }
	$(PIP) install -e "$(ASICFLOW_REPO)[dev]"

validate:
	@test -d "$(ORFS_FLOW)" || { echo "ORFS_FLOW not found: $(ORFS_FLOW)"; exit 1; }
	@test "$(PLATFORM)" != "sky130hd" || test -d "$(PDK_ROOT)" || { echo "PDK_ROOT not found: $(PDK_ROOT)"; exit 1; }
	@$(ASICFLOW) validate $(FLOW_ARGS)
	@$(PYTHON) "$(ROOT)/scripts/validate_design.py" --root "$(ROOT)" --platform "$(PLATFORM)" --design-config "$(DESIGN_CONFIG)"

project-validate:
	@$(ORFSX) --config "$(PROJECT_CONFIG)" validate

project-synth:
	@$(ORFSX) --config "$(PROJECT_CONFIG)" run synth

project-floorplan:
	@$(ORFSX) --config "$(PROJECT_CONFIG)" run floorplan

project-place:
	@$(ORFSX) --config "$(PROJECT_CONFIG)" run place

project-cts:
	@$(ORFSX) --config "$(PROJECT_CONFIG)" run cts

project-route:
	@$(ORFSX) --config "$(PROJECT_CONFIG)" run route

project-finish:
	@$(ORFSX) --config "$(PROJECT_CONFIG)" run finish

project-gui:
	@$(ORFSX) --config "$(PROJECT_CONFIG)" gui "$(GUI_TARGET)"

project-sta:
	@$(ORFSX) --config "$(PROJECT_CONFIG)" sta --stage "$(STA_STAGE)" $(if $(filter 1,$(STA_ALL_CORNERS)),--all-corners,) $(if $(STA_CORNER),--corner "$(STA_CORNER)",)

synth:
	@$(ASICFLOW) synth $(FLOW_ARGS)

floorplan place cts route finish:
	@$(ASICFLOW) $@ $(FLOW_ARGS) $(if $(filter 1,$(STA_AFTER)),--sta,)

flow:
	@$(ASICFLOW) flow $(FLOW_ARGS) $(if $(filter 1,$(STA_AFTER)),--sta,)

gui:
	@test -f "$(RESULTS_DIR)/$(GUI_ODB)" || { \
		echo "Cannot open $(GUI_TARGET): missing $(RESULTS_DIR)/$(GUI_ODB)"; \
		echo "Matching ODB files available under $(ROOT)/build/runs/$(PLATFORM):"; \
		find "$(ROOT)/build/runs/$(PLATFORM)" -type f -name "$(GUI_ODB)" -print 2>/dev/null || true; \
		exit 1; \
	}
	@$(MAKE) --no-print-directory -C "$(ORFS_FLOW)" \
		DESIGN_CONFIG="$(abspath $(DESIGN_CONFIG))" \
		PLATFORM="$(PLATFORM)" \
		PDK_ROOT="$(PDK_ROOT)" \
		RUN_TAG="$(RUN_TAG)" \
		FLOW_VARIANT="$(FLOW_VARIANT)" \
		WORK_HOME="$(WORK_HOME)" \
		"$(GUI_ORFS_TARGET)"

gui-place:
	@$(MAKE) --no-print-directory gui GUI_TARGET=place

sta-pvt:
	@$(ASICFLOW) sta-pvt $(FLOW_ARGS) --stage "$(STA_STAGE)" $(if $(filter 1,$(STA_ALL_CORNERS)),--all-corners,) $(if $(STA_PATHS),--paths "$(STA_PATHS)",) $(if $(BASELINE_TAG),--baseline "$(BASELINE_TAG)",)

sta-shell:
	@$(ASICFLOW) sta-shell $(FLOW_ARGS) --stage "$(STA_STAGE)" $(if $(STA_CORNER),--corner "$(STA_CORNER)",)

presta:
	@$(ASICFLOW) presta $(FLOW_ARGS) $(if $(filter 1,$(INTERACTIVE)),--shell,)

predict:
	@$(ASICFLOW) predict $(FLOW_ARGS) $(if $(filter 1,$(FAIL_IF_UNROUTABLE)),--fail-if-unroutable,)

place-predict:
	@$(ASICFLOW) place-predict $(FLOW_ARGS) $(if $(filter 1,$(FAIL_IF_UNROUTABLE)),--fail-if-unroutable,)

place-gen:
ifeq ($(strip $(SIDE)$(NAME)),)
	@$(ASICFLOW) place-gen --presets $(FLOW_ARGS)
else
	@test -n "$(SIDE)" -a -n "$(NAME)" || { echo 'SIDE and NAME must be set together'; exit 2; }
	@$(ASICFLOW) place-gen --side "$(SIDE)" --name "$(NAME)" --gap "$(or $(GAP),20)" --chan "$(or $(CHAN),60)" $(FLOW_ARGS)
endif

metrics:
	@$(ASICFLOW) metrics $(FLOW_ARGS) --stage "$(METRICS_STAGE)" --runs "$(or $(METRICS_RUNS),$(RUN_TAG))" --corners "$(or $(METRICS_CORNERS),default)" $(if $(filter 1,$(METRICS_HPWL)),--hpwl,) $(if $(METRICS_SAIF),--saif "$(METRICS_SAIF)",) --saif-scope "$(or $(METRICS_SAIF_SCOPE),tb/dut)" $(if $(METRICS_OUTROOT),--outroot "$(METRICS_OUTROOT)",)

metrics-all:
	@$(ASICFLOW) metrics $(FLOW_ARGS) --all-stages --runs "$(or $(METRICS_RUNS),$(RUN_TAG))" --corners "$(or $(METRICS_CORNERS),default)" $(if $(filter 1,$(METRICS_HPWL)),--hpwl,) $(if $(METRICS_OUTROOT),--outroot "$(METRICS_OUTROOT)",)

metrics-export:
	@$(ASICFLOW) metrics $(FLOW_ARGS) --export "$(or $(METRICS_FEATURES),$(ROOT)/build/analysis/features.csv)" --runs "$(or $(METRICS_RUNS),$(RUN_TAG))" $(if $(METRICS_OUTROOT),--outroot "$(METRICS_OUTROOT)",)

sweep:
	@test -n "$(WHAT)" || { echo 'Usage: make sweep WHAT=clock|util|buffering|density|corners|liberty VALUES="..."'; exit 2; }
	@$(ASICFLOW) sweep "$(WHAT)" $(VALUES) $(FLOW_ARGS) --stage "$(or $(SWEEP_STAGE),finish)" $(if $(filter 1,$(SWEEP_EXECUTE)),--execute,)

query:
	@$(ASICFLOW) query $(FLOW_ARGS) --stage "$(QUERY_STAGE)" --category "$(or $(CATEGORY),timing)" $(if $(DB),--db "$(DB)",)

report:
	@$(ASICFLOW) report $(FLOW_ARGS) --limit "$(or $(LIMIT),20)" $(if $(DB),--db "$(DB)",)

set-baseline:
	@$(ASICFLOW) set-baseline $(FLOW_ARGS) --stage "$(ANALYSIS_STAGE)" $(if $(BASELINE_TAG),--tag "$(BASELINE_TAG)",)

summary:
	@$(ASICFLOW) summary $(FLOW_ARGS) --stage "$(ANALYSIS_STAGE)" $(if $(BASELINE_TAG),--baseline "$(BASELINE_TAG)",)

regression:
	@$(ASICFLOW) regression $(FLOW_ARGS) --stage "$(ANALYSIS_STAGE)" --baseline "$(or $(BASELINE_TAG),baseline)"

analyze:
	@test -n "$(WHAT)" || { echo 'Usage: make analyze WHAT=path-groups|fanout|congestion|buffers|macros|area|wirelength|clocks|unconstrained'; exit 2; }
	@$(ASICFLOW) analyze "$(WHAT)" $(FLOW_ARGS) --stage "$(ANALYSIS_STAGE)"

dataset:
	@$(ASICFLOW) dataset --ingest $(FLOW_ARGS) --stage "$(ANALYSIS_STAGE)"

compare-best:
	@test -n "$(TAGS)" || { echo "Usage: make compare-best TAGS='tag1 tag2 tag3'"; exit 2; }
	@$(ASICFLOW) compare best $(TAGS) $(FLOW_ARGS) --stage "$(ANALYSIS_STAGE)"

netlist:
	@$(ASICFLOW) netlist $(FLOW_ARGS) --stage "$(STAGE)"

presta-both:
	$(MAKE) --no-print-directory presta PLATFORM=sky130hd RUN_TAG="$(RUN_TAG)"
	$(MAKE) --no-print-directory presta PLATFORM=nangate45 RUN_TAG="$(RUN_TAG)"

lint:
	verilator --lint-only -Wall -Wno-fatal $(ROOT)/lint.vlt $(RTL_SOURCES) --top-module sys_top

test:
	$(MAKE) --no-print-directory -C "$(TB)" test-all

regress:
	$(MAKE) --no-print-directory -C "$(TB)" sim TOPLEVEL=sys_top MODULE=test_sys_top_apb

gl-regress: netlist
	@test -n "$(NETLIST)" || { echo "No gate-level netlist mapping for STAGE=$(STAGE)"; exit 2; }
	@test -f "$(NETLIST)" || { echo "Missing $(NETLIST)"; exit 1; }
	$(MAKE) --no-print-directory -C "$(TB)" sim TOPLEVEL=sys_top MODULE=test_sys_top_apb NETLIST="$(NETLIST)" CELL_LIBS="$(CELL_LIBS)" GL_TAG="$(or $(GL_TAG),$(PLATFORM)_$(RUN_TAG)_$(STAGE))"

regress-frontend:
	@test -f "$(FRONTEND_RTLIL)" || { echo "Missing $(FRONTEND_RTLIL); run synthesis first"; exit 1; }
	@mkdir -p "$(RESULTS_DIR)"
	yosys -q -p "read_rtlil $(FRONTEND_RTLIL); hierarchy -top sys_top; proc; flatten; opt_clean; write_verilog -noattr $(FRONTEND_V)"
	$(MAKE) --no-print-directory -C "$(TB)" sim TOPLEVEL=sys_top MODULE=test_sys_top_apb NETLIST="$(FRONTEND_V)"

gl-check: netlist
	@test -n "$(NETLIST)" || { echo "No gate-level netlist mapping for STAGE=$(STAGE)"; exit 2; }
	@set -eu; \
	  test -f "$(NETLIST)" || { echo "Missing $(NETLIST)"; exit 1; }; \
	  mkdir -p "$(WORK_HOME)/checks"; \
	  verilator --lint-only -Wall -Wno-fatal --timing -DFUNCTIONAL -DUNIT_DELAY= --top-module sys_top "$(NETLIST)" $(CELL_LIBS) "$(TB)/models/fakeram_sim.v" >"$(WORK_HOME)/checks/gl_lint.log" 2>&1 || { cat "$(WORK_HOME)/checks/gl_lint.log"; exit 1; }; \
	  cat "$(WORK_HOME)/checks/gl_lint.log"

csr:
	@test -f "$(CSR_RDL)" || { echo "Missing $(CSR_RDL)"; exit 1; }
	mkdir -p "$(CSR_OUT)"
	$(PEAKRDL) regblock "$(CSR_RDL)" -o "$(CSR_OUT)" --cpuif apb4-flat --default-reset arst_n
	$(PEAKRDL) c-header "$(CSR_RDL)" -o "$(CSR_OUT)/my_csr.h"

fakeram:
	@test -f "$(FAKERAM_CONFIG)" || { echo "Missing Fakeram config: $(FAKERAM_CONFIG)"; exit 1; }
	@test -n "$(BSG_FAKERAM_ROOT)" -o -d "$(HOME)/eda/bsg_fakeram" || { echo 'Set BSG_FAKERAM_ROOT or install bsg_fakeram at ~/eda/bsg_fakeram'; exit 1; }
	cd "$(or $(BSG_FAKERAM_ROOT),$(HOME)/eda/bsg_fakeram)" && $(PYTHON) scripts/run.py "$(FAKERAM_CONFIG)" --output_dir "$(FAKERAM_DIR)" --cacti_dir "$(or $(CACTI_BUILD_DIR),$(HOME)/eda/bsg_fakeram/tools/cacti)"
ifeq ($(PLATFORM),sky130hd)
	@$(ASICFLOW) fix-lef "$(FAKERAM_DIR)/sram_sp_64x64/sram_sp_64x64.lef" "$(FAKERAM_DIR)/sram_sp_64x256/sram_sp_64x256.lef"
endif

clean:
	@rm -rf "$(ROOT)/build/lint_"* "$(ROOT)/obj_dir" "$(ROOT)/results.xml"
	@$(MAKE) --no-print-directory -C "$(TB)" -f "$(TB)/clean.mk"

distclean: clean
	@find "$(ROOT)" -path "$(ROOT)/.venv" -prune -o -type d -name __pycache__ -prune -exec rm -rf {} +
	@find "$(ROOT)" -path "$(ROOT)/.venv" -prune -o -type f -name '*.pyc' -delete
