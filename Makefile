.DEFAULT_GOAL := help
.SUFFIXES:
MAKEFLAGS += --no-builtin-rules

ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
PYTHON ?= $(if $(wildcard $(ROOT)/.venv/bin/python3),$(ROOT)/.venv/bin/python3,python3)
PIP ?= $(PYTHON) -m pip
ASICFLOW_REPO ?= $(abspath $(ROOT)/../orfs-custom)
ASICFLOW := $(PYTHON) -m asicflow.flow
PEAKRDL ?= peakrdl

PLATFORM ?= sky130hd
ifeq ($(PLATFORM),sky130)
override PLATFORM := sky130hd
endif
RUN_TAG ?= base
FLOW_VARIANT ?= base
PLACEMENT ?= rtlmp
STAGE ?= latest
GUI_TARGET ?= final

ORFS_FLOW ?= $(HOME)/eda/orfs-nix/OpenROAD-flow-scripts/flow
PDK_ROOT ?= $(HOME)/eda/.volare
DESIGN_CONFIG ?= design-configs/$(PLATFORM).mk
WORK_HOME ?= $(ROOT)/build/runs/$(PLATFORM)/systolic_array/$(RUN_TAG)
ASICFLOW_CONFIG_DIR ?= $(ROOT)/config
ASICFLOW_DESIGN_PROFILE ?= $(ROOT)/config/designs/systolic_array.yaml

export ROOT_DIR := $(ROOT)
export ORFS_FLOW PDK_ROOT PLATFORM RUN_TAG FLOW_VARIANT PLACEMENT
export DESIGN_CONFIG WORK_HOME ASICFLOW_CONFIG_DIR ASICFLOW_DESIGN_PROFILE

FLOW_ARGS = --platform "$(PLATFORM)" --run-tag "$(RUN_TAG)" --flow-variant "$(FLOW_VARIANT)" --placement "$(PLACEMENT)" --design-config "$(DESIGN_CONFIG)" --work-home "$(WORK_HOME)" --config-dir "$(ASICFLOW_CONFIG_DIR)" --design-profile "$(ASICFLOW_DESIGN_PROFILE)"
RTL_FILELIST := $(ROOT)/rtl/files.f
RTL_SOURCES := $(addprefix $(ROOT)/rtl/,$(shell sed -e 's/[[:space:]]*#.*$$//' -e '/^[[:space:]]*$$/d' "$(RTL_FILELIST)"))
TB := $(ROOT)/tb
CSR_RDL := $(ROOT)/csr/my_csr.rdl
CSR_OUT := $(ROOT)/rtl/csr_generated
FAKERAM_TECH := $(if $(filter sky130hd,$(PLATFORM)),sky130,$(PLATFORM))
FAKERAM_DIR := $(ROOT)/fakeram/$(FAKERAM_TECH)
FAKERAM_CONFIG := $(FAKERAM_DIR)_fakeram.cfg

ifeq ($(PLATFORM),sky130hd)
CELL_LIBS ?= $(PDK_ROOT)/sky130A/libs.ref/sky130_fd_sc_hd/verilog/primitives.v $(PDK_ROOT)/sky130A/libs.ref/sky130_fd_sc_hd/verilog/sky130_fd_sc_hd.v
else ifeq ($(PLATFORM),nangate45)
CELL_LIBS ?= $(TB)/models/nangate45/NangateOpenCellLibrary.v
else
$(error Unsupported PLATFORM '$(PLATFORM)'; use sky130hd or nangate45)
endif

.PHONY: help install validate lint test csr fakeram synth floorplan place cts route finish flow gui sta-pvt sta-shell presta predict place-predict place-gen metrics metrics-all metrics-export query report set-baseline summary regression analyze dataset compare-best netlist regress regress-frontend gl-check clean distclean synth-sta synth-sta-both

help:
	@printf '%s\n' \
	  'ASICFlow / ORFS' \
	  '  make install [ASICFLOW_REPO=../orfs-custom]' \
	  '  make validate PLATFORM=sky130hd|nangate45' \
	  '  make synth|floorplan|place|cts|route|finish|flow RUN_TAG=baseline' \
	  '  make sta-pvt STAGE=latest | make metrics STAGE=place' \
	  '  make metrics-all | make report | make query CATEGORY=timing' \
	  '  make gui GUI_TARGET=place | make place-gen SIDE=left NAME=left' \
	  '  make lint | test | regress | gl-check' \
	  '  RUN_TAG separates experiments; FLOW_VARIANT separates ORFS variants.'

install:
	$(PIP) install -e "$(ASICFLOW_REPO)[dev]"

validate:
	@test -d "$(ORFS_FLOW)" || { echo "ORFS_FLOW not found: $(ORFS_FLOW)"; exit 1; }
	@test -d "$(PDK_ROOT)" || { echo "PDK_ROOT not found: $(PDK_ROOT)"; exit 1; }
	@$(ASICFLOW) validate $(FLOW_ARGS)
	@$(PYTHON) "$(ROOT)/scripts/validate_design.py" --root "$(ROOT)" --platform "$(PLATFORM)" --design-config "$(DESIGN_CONFIG)"

synth floorplan place cts route finish:
	@$(ASICFLOW) $@ $(FLOW_ARGS) $(if $(filter 1,$(STA_AFTER)),--sta,)

flow:
	@$(ASICFLOW) flow $(FLOW_ARGS) $(if $(filter 1,$(STA_AFTER)),--sta,)

gui:
	@$(ASICFLOW) gui "$(GUI_TARGET)" $(FLOW_ARGS)

sta-pvt:
	@$(ASICFLOW) sta-pvt $(FLOW_ARGS) --stage "$(STAGE)" $(if $(filter 1,$(STA_ALL_CORNERS)),--all-corners,) $(if $(STA_PATHS),--paths "$(STA_PATHS)",) $(if $(BASELINE_TAG),--baseline "$(BASELINE_TAG)",)

sta-shell:
	@$(ASICFLOW) sta-shell $(FLOW_ARGS) --stage "$(STAGE)" $(if $(STA_CORNER),--corner "$(STA_CORNER)",)

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
	@$(ASICFLOW) metrics $(FLOW_ARGS) --stage "$(or $(METRICS_STAGE),$(STAGE))" --runs "$(or $(METRICS_RUNS),$(RUN_TAG))" --corners "$(or $(METRICS_CORNERS),default)" $(if $(filter 1,$(METRICS_HPWL)),--hpwl,) $(if $(METRICS_SAIF),--saif "$(METRICS_SAIF)",) --saif-scope "$(or $(METRICS_SAIF_SCOPE),tb/dut)" $(if $(METRICS_OUTROOT),--outroot "$(METRICS_OUTROOT)",)

metrics-all:
	@$(ASICFLOW) metrics $(FLOW_ARGS) --all-stages --runs "$(or $(METRICS_RUNS),$(RUN_TAG))" --corners "$(or $(METRICS_CORNERS),default)" $(if $(filter 1,$(METRICS_HPWL)),--hpwl,) $(if $(METRICS_OUTROOT),--outroot "$(METRICS_OUTROOT)",)

metrics-export:
	@$(ASICFLOW) metrics $(FLOW_ARGS) --export "$(or $(METRICS_FEATURES),$(ROOT)/build/analysis/features.csv)" --runs "$(or $(METRICS_RUNS),$(RUN_TAG))" $(if $(METRICS_OUTROOT),--outroot "$(METRICS_OUTROOT)",)

query:
	@$(ASICFLOW) query $(FLOW_ARGS) --stage "$(STAGE)" --category "$(or $(CATEGORY),timing)" $(if $(DB),--db "$(DB)",)

report:
	@$(ASICFLOW) report $(FLOW_ARGS) --limit "$(or $(LIMIT),20)" $(if $(DB),--db "$(DB)",)

set-baseline:
	@$(ASICFLOW) set-baseline $(FLOW_ARGS) --stage "$(STAGE)" $(if $(BASELINE_TAG),--tag "$(BASELINE_TAG)",)

summary:
	@$(ASICFLOW) summary $(FLOW_ARGS) --stage "$(STAGE)" $(if $(BASELINE_TAG),--baseline "$(BASELINE_TAG)",)

regression:
	@$(ASICFLOW) regression $(FLOW_ARGS) --stage "$(STAGE)" --baseline "$(or $(BASELINE_TAG),baseline)"

analyze:
	@test -n "$(WHAT)" || { echo 'Usage: make analyze WHAT=path-groups|fanout|congestion|buffers|macros|area|wirelength|clocks|unconstrained'; exit 2; }
	@$(ASICFLOW) analyze "$(WHAT)" $(FLOW_ARGS) --stage "$(STAGE)"

dataset:
	@$(ASICFLOW) dataset --ingest $(FLOW_ARGS) --stage "$(STAGE)"

compare-best:
	@test -n "$(TAGS)" || { echo "Usage: make compare-best TAGS='tag1 tag2 tag3'"; exit 2; }
	@$(ASICFLOW) compare best $(TAGS) $(FLOW_ARGS) --stage "$(STAGE)"

netlist:
	@$(ASICFLOW) netlist $(FLOW_ARGS) --stage "$(STAGE)"

synth-sta:
	$(MAKE) --no-print-directory synth
	$(MAKE) --no-print-directory sta-pvt STAGE=synth

synth-sta-both:
	$(MAKE) --no-print-directory synth PLATFORM=sky130hd RUN_TAG="$(RUN_TAG)"
	$(MAKE) --no-print-directory synth PLATFORM=nangate45 RUN_TAG="$(RUN_TAG)"
	$(MAKE) --no-print-directory sta-pvt PLATFORM=sky130hd RUN_TAG="$(RUN_TAG)" STAGE=synth
	$(MAKE) --no-print-directory sta-pvt PLATFORM=nangate45 RUN_TAG="$(RUN_TAG)" STAGE=synth

lint:
	verilator --lint-only -Wall -Wno-fatal $(ROOT)/lint.vlt $(RTL_SOURCES) --top-module sys_top

test:
	$(MAKE) --no-print-directory -C "$(TB)" test-all

regress:
	$(MAKE) --no-print-directory -C "$(TB)" sim TOPLEVEL=sys_top MODULE=test_sys_top_apb

regress-frontend:
	@test -f "$(WORK_HOME)/results/$(PLATFORM)/systolic_array/$(FLOW_VARIANT)/0_frontend.v" || { echo 'Frontend netlist not found; run synthesis first and check RTLIL export'; exit 1; }
	$(MAKE) --no-print-directory -C "$(TB)" sim TOPLEVEL=sys_top MODULE=test_sys_top_apb NETLIST="$(WORK_HOME)/results/$(PLATFORM)/systolic_array/$(FLOW_VARIANT)/0_frontend.v"

gl-check: netlist
	@set -eu; \
	  test -n "$(NETLIST)" || { echo 'Set NETLIST to the stage netlist path'; exit 2; }; \
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
