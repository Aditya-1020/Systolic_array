.DEFAULT_GOAL := help
.SUFFIXES:
MAKEFLAGS += --no-builtin-rules

ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
RTL := $(ROOT)/rtl
TB := $(ROOT)/tb
PYTHON ?= $(if $(wildcard $(ROOT)/.venv/bin/python3),$(ROOT)/.venv/bin/python3,python3)
export PYTHONPATH := $(ROOT)$(if $(PYTHONPATH),:$(PYTHONPATH))
FLOW := $(PYTHON) -m asicflow

CSR_RDL    := $(ROOT)/csr/my_csr.rdl
CSR_OUT    := $(RTL)/csr_generated
CSR_HEADER := $(CSR_OUT)/my_csr.h
RTL_FILELIST := $(RTL)/files.f
SIM_FILELIST := $(TB)/files_sim.f
PEAKRDL ?= peakrdl

rtl_src = $(addprefix $(RTL)/,$(filter-out cells_clkgate.v,$(shell \
	sed -e 's/[[:space:]]*#.*$$//' \
	    -e '/^[[:space:]]*$$/d' "$(RTL_FILELIST)")))
sim_src = $(addprefix $(TB)/,$(shell \
	sed -e 's/[[:space:]]*#.*$$//' \
	    -e '/^[[:space:]]*$$/d' "$(SIM_FILELIST)"))

export ROOT_DIR := $(ROOT)
ORFS_FLOW ?= $(HOME)/eda/orfs-nix/OpenROAD-flow-scripts/flow
PDK_ROOT ?= $(HOME)/eda/.volare
export ORFS_FLOW PDK_ROOT

PLATFORM ?= sky130hd
ifneq ($(origin TECH),undefined)
  ifeq ($(TECH),sky130)
    override PLATFORM := sky130hd
  else
    override PLATFORM := $(TECH)
  endif
endif
ifeq ($(PLATFORM),sky130)
  override PLATFORM := sky130hd
endif

RUN_TAG ?= base
FLOW_VARIANT ?= base
STAGE ?= synth
GL_DELAY ?= 0
PLACEMENT ?= rtlmp
DESIGN_CONFIG ?=
WORK_HOME ?=
CORE_UTILIZATION ?=
STA_AFTER ?= 0
STA_JOBS ?= 6
export STA_JOBS

ifneq ($(strip $(CORE_UTILIZATION)),)
export CORE_UTILIZATION
endif

FLOW_ARGS = --platform $(PLATFORM) --run-tag $(RUN_TAG) --flow-variant $(FLOW_VARIANT) --placement $(PLACEMENT)
ifneq ($(strip $(DESIGN_CONFIG)),)
FLOW_ARGS += --design-config $(DESIGN_CONFIG)
endif
ifneq ($(strip $(WORK_HOME)),)
FLOW_ARGS += --work-home $(WORK_HOME)
endif

# Design-config resolves DESIGN_NICKNAME / FAKERAM_TECH; Makefile mirrors for regress paths.
ifeq ($(strip $(DESIGN_CONFIG)),)
    CFG := $(abspath $(ROOT)/design-configs/$(PLATFORM).mk)
else ifeq ($(filter /%,$(DESIGN_CONFIG)),)
    CFG := $(abspath $(ROOT)/$(DESIGN_CONFIG))
else
    CFG := $(abspath $(DESIGN_CONFIG))
endif

DESIGN_NICKNAME := $(shell sed -n 's/^export DESIGN_NICKNAME *= *//p' "$(CFG)" | head -1)
FAKERAM_TECH := $(shell sed -n 's/^export FAKERAM_TECH *= *//p' "$(CFG)" | head -1)
ifeq ($(strip $(DESIGN_NICKNAME)),)
DESIGN_NICKNAME := systolic_array
endif
ifeq ($(strip $(FAKERAM_TECH)),)
FAKERAM_TECH := $(PLATFORM)
endif

ifeq ($(strip $(WORK_HOME)),)
WORK_HOME_RES := $(ROOT)/build/runs/$(PLATFORM)/$(DESIGN_NICKNAME)/$(RUN_TAG)
else
WORK_HOME_RES := $(WORK_HOME)
endif
RESULTS_DIR := $(WORK_HOME_RES)/results/$(PLATFORM)/$(DESIGN_NICKNAME)/$(FLOW_VARIANT)

# Netlist names are defined only for canonical asicflow stages. STA can use
# any exact ODB stem (for example, 3_5_place_dp) and must not be rejected here.
NETLIST_STAGES := synth floorplan place cts route final finish
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
else ifeq ($(STAGE),final)
    NETLIST_NAME := 6_final.v
else ifeq ($(STAGE),finish)
    NETLIST_NAME := 6_final.v
else
    NETLIST_NAME :=
endif
NETLIST := $(if $(strip $(NETLIST_NAME)),$(RESULTS_DIR)/$(NETLIST_NAME),)

# Simulation cell libraries (Makefile owns gate-level sim collateral).
ifeq ($(PLATFORM),sky130hd)
    CELL_LIBS ?= \
        $(PDK_ROOT)/sky130A/libs.ref/sky130_fd_sc_hd/verilog/primitives.v \
        $(PDK_ROOT)/sky130A/libs.ref/sky130_fd_sc_hd/verilog/sky130_fd_sc_hd.v
else ifeq ($(PLATFORM),nangate45)
    CELL_VERILOG ?= $(ROOT)/tb/models/nangate45/NangateOpenCellLibrary.v
    CELL_LIBS ?= $(CELL_VERILOG)
else
    $(error Unsupported PLATFORM='$(PLATFORM)'. Use PLATFORM=sky130hd or PLATFORM=nangate45)
endif

FAKERAM_DIR := $(ROOT)/fakeram/$(FAKERAM_TECH)
FAKERAM_CFG := $(ROOT)/fakeram/$(FAKERAM_TECH)_fakeram.cfg
MEM_MACROS  := sram_sp_64x64 sram_sp_64x256
CACTI_BUILD_DIR ?= $(HOME)/eda/bsg_fakeram/tools/cacti

METRICS_STAGE      ?= $(STAGE)
METRICS_RUNS       ?= $(RUN_TAG)
METRICS_OUTROOT    ?= $(dir $(abspath $(WORK_HOME_RES)))
METRICS_CORNERS    ?= default
METRICS_HPWL       ?= 0
METRICS_SAIF       ?=
METRICS_SAIF_SCOPE ?= tb/dut
METRICS_FEATURES   ?= $(ROOT)/build/analysis/features.csv

.PHONY: help
help:
	@printf '%s\n' \
	    'Make → python3 -m asicflow' \
	    '' \
	    '  PLATFORM=sky130hd|nangate45   RUN_TAG=<exp>   FLOW_VARIANT=base' \
	    '  PLACEMENT=rtlmp|<name>' \
	    '' \
	    '  make validate PLATFORM=sky130hd' \
	    '  make synth|place|cts|route|finish|flow PLATFORM=sky130hd RUN_TAG=baseline' \
	    '  make sta-pvt PLATFORM=sky130hd RUN_TAG=baseline STAGE=synth' \
	    '  make sta-pvt RUN_TAG=pd_60util STAGE=3_5_place_dp  # exact ODB stem' \
	    '  make place && make sta-pvt STAGE=place   # STAGE must match completed ORFS step' \
	    '  make sta-shell PLATFORM=sky130hd RUN_TAG=baseline STAGE=synth' \
	    '  make synth-sta-both RUN_TAG=baseline STAGE=synth' \
	    '  make regress PLATFORM=sky130hd RUN_TAG=baseline' \
	    '' \
	    '  make set-baseline RUN_TAG=baseline STAGE=final' \
	    '  make summary STAGE=final BASELINE_TAG=baseline' \
	    '  make analyze WHAT=path-groups|fanout|congestion|buffers|macros|area|…' \
	    '  make dataset-plot STAGE=final' \
	    '' \
	    '  make place-gen SIDE=left NAME=my_left' \
	    '  make baseline' \
	    '' \
	    'WORK_HOME=$(WORK_HOME_RES)' \
	    'RESULTS_DIR=$(RESULTS_DIR)'

.PHONY: place-gen
place-gen:
ifeq ($(SIDE)$(NAME),)
	@$(FLOW) place-gen --presets $(FLOW_ARGS)
else
	@$(FLOW) place-gen --side $(SIDE) --name $(NAME) \
	    --gap $(or $(GAP),20) --chan $(or $(CHAN),60) $(FLOW_ARGS)
endif

.PHONY: lint test csr
lint:
	verilator --lint-only -Wall -Wno-fatal \
	    $(ROOT)/lint.vlt $(rtl_src) $(sim_src) --top-module sys_top

test:
	$(MAKE) --no-print-directory -C "$(TB)" test-all

csr:
	@test -f "$(CSR_RDL)" || { echo "ERROR: missing $(CSR_RDL)"; exit 1; }
	@mkdir -p "$(CSR_OUT)"
	$(PEAKRDL) regblock "$(CSR_RDL)" -o "$(CSR_OUT)" --cpuif apb4-flat --default-reset arst_n
	$(PEAKRDL) c-header "$(CSR_RDL)" -o "$(CSR_HEADER)"

.PHONY: validate
validate:
	@$(FLOW) validate $(FLOW_ARGS)

.PHONY: fakeram
fakeram:
	@test -f "$(FAKERAM_CFG)" || { echo "ERROR: missing $(FAKERAM_CFG)"; exit 1; }
	cd "$(HOME)/eda/bsg_fakeram" && \
	    $(PYTHON) scripts/run.py "$(FAKERAM_CFG)" \
	        --output_dir "$(FAKERAM_DIR)" --cacti_dir "$(CACTI_BUILD_DIR)"
ifeq ($(PLATFORM),sky130hd)
	@set -e; for m in $(MEM_MACROS); do \
	    $(FLOW) fix-lef "$(FAKERAM_DIR)/$$m/$$m.lef"; \
	done
endif

.PHONY: synth floorplan place cts route finish flow flow-all predict place-predict baseline
synth floorplan place cts route finish:
	@$(FLOW) $@ $(FLOW_ARGS) $(if $(filter 1,$(STA_AFTER)),--sta,)

predict:
	@$(FLOW) predict $(FLOW_ARGS) $(if $(FAIL_IF_UNROUTABLE),--fail-if-unroutable,)

place-predict:
	@$(FLOW) place-predict $(FLOW_ARGS) $(if $(FAIL_IF_UNROUTABLE),--fail-if-unroutable,)

flow:
	@$(FLOW) flow $(FLOW_ARGS) $(if $(filter 1,$(STA_AFTER)),--sta,)

baseline:
	@$(FLOW) place-gen --side left --name baseline --gap 30 --chan 100 $(FLOW_ARGS) \
	    --run-tag baseline
	$(MAKE) --no-print-directory flow \
	    RUN_TAG=baseline PLACEMENT=baseline CORE_UTILIZATION=30 STA_AFTER=1

flow-all:
	$(MAKE) --no-print-directory flow PLATFORM=sky130hd
	$(MAKE) --no-print-directory flow PLATFORM=nangate45

.PHONY: gui_synth gui_floorplan gui_place gui_cts gui_route gui_final
gui_synth gui_floorplan gui_place gui_cts gui_route gui_final:
	@$(FLOW) gui $(patsubst gui_%,%,$@) $(FLOW_ARGS)

.PHONY: netlist
netlist:
	@case " $(NETLIST_STAGES) " in *" $(STAGE) "*) ;; *) \
	    echo "ERROR: STAGE='$(STAGE)' has no registered gate-level netlist mapping."; \
	    echo "Use one of: $(NETLIST_STAGES)"; exit 2 ;; esac
	@$(FLOW) netlist --stage $(STAGE) $(FLOW_ARGS)

.PHONY: gl-check
gl-check: netlist
	@set -eu; mkdir -p "$(RESULTS_DIR)"; \
	log="$(RESULTS_DIR)/gl_lint.log"; \
	verilator --lint-only -Wall -Wno-fatal --timing \
	    -DFUNCTIONAL -DUNIT_DELAY= --top-module sys_top \
	    "$(NETLIST)" $(CELL_LIBS) "$(TB)/models/fakeram_sim.v" >"$$log" 2>&1 || true; \
	if grep -E '%Warning-(PINNOTFOUND|MULTIDRIVEN)|%Error' "$$log"; then \
	    echo "gl-check FAILED, see $$log"; exit 1; \
	fi; \
	echo "gl-check OK ($$log)"

FRONTEND_RTLIL ?= $(RESULTS_DIR)/1_1_yosys_canonicalize.rtlil
FRONTEND_V := $(RESULTS_DIR)/0_frontend.v

.PHONY: regress-frontend
regress-frontend: netlist
	@test -f "$(FRONTEND_RTLIL)" || { echo "ERROR: missing $(FRONTEND_RTLIL)"; exit 1; }
	yosys -q -p "read_rtlil $(FRONTEND_RTLIL); hierarchy -top sys_top; proc; flatten; opt_clean; write_verilog -noattr $(FRONTEND_V)"
	$(MAKE) --no-print-directory -C "$(TB)" sim \
	    TOPLEVEL=sys_top MODULE=test_sys_top_apb \
	    NETLIST="$(FRONTEND_V)" CELL_LIBS="$(CELL_LIBS)" \
	    GL_TAG="$(PLATFORM)_$(RUN_TAG)_frontend"

.PHONY: regress
regress: netlist
	@set -eu; \
	if [ -z "$(strip $(CELL_LIBS))" ]; then \
	    echo "ERROR: no CELL_LIBS for PLATFORM=$(PLATFORM)"; exit 1; \
	fi; \
	for f in $(CELL_LIBS); do test -f "$$f" || { echo "ERROR: missing $$f"; exit 1; }; done; \
	test -f "$(NETLIST)" || { echo "ERROR: missing $(NETLIST)"; exit 1; }; \
	echo "========== GATE-LEVEL REGRESSION =========="; \
	echo "PLATFORM=$(PLATFORM) RUN_TAG=$(RUN_TAG) STAGE=$(STAGE) NETLIST=$(NETLIST)"; \
	$(MAKE) --no-print-directory -C "$(TB)" sim \
	    TOPLEVEL=sys_top MODULE=test_sys_top_apb \
	    NETLIST="$(abspath $(NETLIST))" CELL_LIBS="$(CELL_LIBS)" \
	    GL_TAG="$(PLATFORM)_$(RUN_TAG)_$(FLOW_VARIANT)_$(STAGE)" GL_DELAY="$(GL_DELAY)"

.PHONY: sta-shell sta-pvt presta presta-shell
sta-shell:
	@$(FLOW) sta-shell --stage $(STAGE) $(FLOW_ARGS) \
	    $(if $(STA_CORNER),--corner $(STA_CORNER),)

sta-pvt:
	@$(FLOW) sta-pvt --stage $(STAGE) $(FLOW_ARGS) \
	    $(if $(filter 1,$(STA_ALL_CORNERS)),--all-corners,) \
	    $(if $(STA_PATHS),--paths $(STA_PATHS),) \
	    $(if $(BASELINE_TAG),--baseline $(BASELINE_TAG),)

.PHONY: set-baseline summary regression analyze dataset-plot compare-best
set-baseline:
	@$(FLOW) set-baseline --stage $(STAGE) $(FLOW_ARGS) \
	    $(if $(BASELINE_TAG),--tag $(BASELINE_TAG),)

summary:
	@$(FLOW) summary --stage $(STAGE) $(FLOW_ARGS) \
	    $(if $(BASELINE_TAG),--baseline $(BASELINE_TAG),)

regression:
	@$(FLOW) regression --stage $(STAGE) $(FLOW_ARGS) \
	    --baseline $(or $(BASELINE_TAG),baseline)

analyze:
	@test -n "$(WHAT)" || { echo "USAGE: make analyze WHAT=path-groups|fanout|congestion|buffers|macros|area|wirelength|clocks|unconstrained"; exit 1; }
	@$(FLOW) analyze $(WHAT) --stage $(STAGE) $(FLOW_ARGS)

dataset-plot:
	@$(FLOW) dataset --ingest --stage $(STAGE) $(FLOW_ARGS)

compare-best:
	@test -n "$(TAGS)" || { echo "USAGE: make compare-best TAGS='a b c'"; exit 1; }
	@$(FLOW) compare best $(TAGS) --stage $(STAGE) $(FLOW_ARGS)

.PHONY: synth-sta-both synth-sta
synth-sta:
	@$(MAKE) --no-print-directory synth PLATFORM=$(PLATFORM) RUN_TAG=$(RUN_TAG) >/dev/null 2>&1
	@$(MAKE) --no-print-directory sta-pvt PLATFORM=$(PLATFORM) RUN_TAG=$(RUN_TAG) STAGE=$(STAGE)

synth-sta-both:
	@set -e; for p in sky130hd nangate45; do \
	    echo "synth $$p RUN_TAG=$(RUN_TAG) …"; \
	    $(MAKE) --no-print-directory synth PLATFORM=$$p RUN_TAG=$(RUN_TAG) >/dev/null 2>&1; \
	done
	@set -e; for p in sky130hd nangate45; do \
	    echo ""; \
	    echo "======== PLATFORM=$$p RUN_TAG=$(RUN_TAG) STAGE=$(STAGE) ========"; \
	    $(MAKE) --no-print-directory sta-pvt PLATFORM=$$p RUN_TAG=$(RUN_TAG) STAGE=$(STAGE); \
	done

presta:
	@$(FLOW) presta $(FLOW_ARGS)

presta-shell:
	@$(FLOW) presta --shell $(FLOW_ARGS)

.PHONY: metrics metrics-all metrics-export
metrics:
	@$(FLOW) metrics --stage $(METRICS_STAGE) --runs "$(METRICS_RUNS)" \
	    --corners "$(METRICS_CORNERS)" \
	    $(if $(filter 1,$(METRICS_HPWL)),--hpwl,) \
	    $(if $(METRICS_SAIF),--saif $(METRICS_SAIF),) \
	    --saif-scope "$(METRICS_SAIF_SCOPE)" \
	    --outroot "$(patsubst %/,%,$(METRICS_OUTROOT))" \
	    $(FLOW_ARGS)

metrics-all:
	@$(FLOW) metrics --all-stages --runs "$(METRICS_RUNS)" \
	    --corners "$(METRICS_CORNERS)" \
	    $(if $(filter 1,$(METRICS_HPWL)),--hpwl,) \
	    --outroot "$(patsubst %/,%,$(METRICS_OUTROOT))" \
	    $(FLOW_ARGS)

metrics-export:
	@$(FLOW) metrics --export "$(METRICS_FEATURES)" --runs "$(METRICS_RUNS)" \
	    --outroot "$(patsubst %/,%,$(METRICS_OUTROOT))" $(FLOW_ARGS)

.PHONY: clean distclean
clean:
	@rm -rf \
		"$(TB)"/sim_build_* \
		"$(TB)"/results*.xml \
		"$(TB)"/*.vcd \
		"$(TB)"/*.fst \
		"$(ROOT)/obj_dir" \
		"$(ROOT)/results.xml" \
		"$(ROOT)"/*.vcd \
		"$(ROOT)"/*.fst \
		"$(ROOT)"/asicflow/__pycache__ \
		"$(ROOT)"/design-configs/__pycache__
	@$(MAKE) --no-print-directory -s -C "$(TB)" -f "$(TB)/clean.mk"

distclean: clean
	find "$(ROOT)" -path "$(ROOT)/.venv" -prune -o \
	    -type d -name __pycache__ -prune -exec rm -rf {} +
	find "$(ROOT)" -path "$(ROOT)/.venv" -prune -o \
	    -type f -name '*.pyc' -delete
