.DEFAULT_GOAL := help

ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
TB_MAKE := $(MAKE) --no-print-directory -C $(ROOT)/tb

ORFS_FLOW ?= $(HOME)/eda/orfs-nix/OpenROAD-flow-scripts/flow

DESIGN_CONFIG ?= $(ROOT)/config/orfs_config/sys_top/sys_top.mk
PLATFORM ?= sky130hd

FLOW_VARIANT ?= base
WORK_HOME ?= $(ROOT)/build/orfs

# AutoTuner configuration. Design-specific files live together under
# config/orfs_config/<design>/.
AUTOTUNER_DIR ?= $(abspath $(ORFS_FLOW)/../tools/AutoTuner)
AUTOTUNER_PYTHON ?= $(AUTOTUNER_DIR)/autotuner_env/bin/python
AUTOTUNER_DESIGN ?= pe
AUTOTUNER_PLATFORM ?= sky130hd
AUTOTUNER_CONFIG ?= $(ROOT)/config/orfs_config/$(AUTOTUNER_DESIGN)/autotuner_$(AUTOTUNER_DESIGN).json
AUTOTUNER_VARIABLES ?= $(ROOT)/config/orfs_config/$(AUTOTUNER_DESIGN)/autotuner_variables.yaml
AUTOTUNER_DESIGN_CONFIG ?= $(ROOT)/config/orfs_config/$(AUTOTUNER_DESIGN)/$(AUTOTUNER_DESIGN).mk
AUTOTUNER_WORK_HOME ?= $(ROOT)/build/autotuner/$(AUTOTUNER_DESIGN)
AUTOTUNER_EXPERIMENT ?= $(AUTOTUNER_DESIGN)_experiment
AUTOTUNER_JOBS ?= 1
AUTOTUNER_THREADS ?= 4
AUTOTUNER_STOP_STAGE ?= place
AUTOTUNER_EXTRA_ARGS ?=

ORFS_MAKE = $(MAKE) --no-print-directory -C "$(ORFS_FLOW)" DESIGN_CONFIG="$(abspath $(DESIGN_CONFIG))" FLOW_VARIANT="$(FLOW_VARIANT)" WORK_HOME="$(abspath $(WORK_HOME))"

METRICS_DESIGN ?= $(basename $(notdir $(DESIGN_CONFIG)))
METRICS_RUN_DIR ?= $(abspath $(WORK_HOME))/results/$(PLATFORM)/$(METRICS_DESIGN)/$(FLOW_VARIANT)
METRICS_OUTPUT_DIR ?= $(abspath $(WORK_HOME))/reports/$(PLATFORM)/$(METRICS_DESIGN)/$(FLOW_VARIANT)/metrics
METRICS_LIBS ?= $(ORFS_FLOW)/platforms/sky130hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
METRICS_LIB_ARGS = $(foreach lib,$(METRICS_LIBS),--lib "$(lib)")



.PHONY: check-orfs
check-orfs:
	@test -f "$(ORFS_FLOW)/Makefile" || { echo "ERROR: ORFS Makefile not found: $(ORFS_FLOW)/Makefile"; exit 1; }
	@test -f "$(DESIGN_CONFIG)" || { echo "ERROR: Design config not found: $(DESIGN_CONFIG)"; exit 1; }

.PHONY: synth floorplan place cts grt route finish all

synth floorplan place cts grt route finish all: check-orfs
	$(ORFS_MAKE) $@


.PHONY: gui
gui: check-orfs
	@test -n "$(GUI_STAGE)" || { echo "Usage: make gui GUI_STAGE=<orfs_stage>"; echo "Example: make gui GUI_STAGE=3_1_place_gp_skip_io"; exit 2; }
	$(ORFS_MAKE) gui_$(GUI_STAGE)

.PHONY: gui-synth gui-floorplan gui-place gui-cts gui-grt gui-route gui-final

gui-synth gui-floorplan gui-place gui-cts gui-grt gui-route gui-final: check-orfs
	$(ORFS_MAKE) gui_$(patsubst gui-%,%,$@)


.PHONY: test test-all test-async-fifo test-pe test-round test-relu test-postproc test-systolic \
        test-sram-wrap-64 test-sram-wrap-256 test-mem-arb test-mem-cdc test-res-wr test-top lint

test test-all:
	$(TB_MAKE) test-all

test-async-fifo:
	$(TB_MAKE) TOPLEVEL=async_fifo_tb_top MODULE=test_async_fifo sim

test-pe:
	$(TB_MAKE) TOPLEVEL=pe MODULE=test_pe sim

test-round:
	$(TB_MAKE) TOPLEVEL=round MODULE=test_round sim

test-relu:
	$(TB_MAKE) TOPLEVEL=relu MODULE=test_relu sim

test-postproc:
	$(TB_MAKE) TOPLEVEL=postproc MODULE=test_postproc sim

test-systolic:
	$(TB_MAKE) test-systolic

test-sram-wrap-64:
	$(TB_MAKE) TOPLEVEL=sram_wrap MODULE=test_sram_wrap SRAM_DEPTH=64 SRAM_ADDR_W=6 sim

test-sram-wrap-256:
	$(TB_MAKE) TOPLEVEL=sram_wrap MODULE=test_sram_wrap SRAM_DEPTH=256 SRAM_ADDR_W=8 sim

test-mem-arb:
	$(TB_MAKE) TOPLEVEL=mem_arb_tb_top MODULE=test_mem_arb sim

test-mem-cdc:
	$(TB_MAKE) test-mem-cdc

test-res-wr:
	$(TB_MAKE) test-res-wr

test-top:
	$(TB_MAKE) test-top

lint:
	$(TB_MAKE) lint

.PHONY: clean clean-tb clean-orfs

# remove simulation outs
clean: clean-tb

clean-tb:
	@find "$(ROOT)" -type d -name '__pycache__' -prune -exec rm -rf {} +
	@rm -rf "$(ROOT)"/tb/sim_build_*
	@rm -f "$(ROOT)"/tb/results*.xml
	@rm -f "$(ROOT)"/tb/*.vcd "$(ROOT)"/tb/*.fst

# remove orfs generated results
clean-orfs: check-orfs
	$(ORFS_MAKE) clean_all

# metrics extractions
.PHONY: metrics-gather

metrics-gather: check-orfs
	@test -d "$(METRICS_RUN_DIR)" || { echo "ERROR: ORFS run directory not found: $(METRICS_RUN_DIR)"; exit 1; }
	@python "$(ROOT)/scripts/extract_metrics.py" \
		--run-dir "$(METRICS_RUN_DIR)" \
		$(METRICS_LIB_ARGS) \
		--output "$(METRICS_OUTPUT_DIR)"


# AutoTuner
.PHONY: check-autotuner autotuner-run autotuner-sweep autotuner-tune

check-autotuner:
	@test -f "$(ORFS_FLOW)/Makefile" || { echo "ERROR: ORFS Makefile not found: $(ORFS_FLOW)/Makefile"; exit 1; }
	@test -x "$(AUTOTUNER_PYTHON)" || { echo "ERROR: AutoTuner Python not found: $(AUTOTUNER_PYTHON)"; exit 1; }
	@test -f "$(AUTOTUNER_CONFIG)" || { echo "ERROR: AutoTuner JSON not found: $(AUTOTUNER_CONFIG)"; exit 1; }
	@test -f "$(AUTOTUNER_VARIABLES)" || { echo "ERROR: AutoTuner YAML not found: $(AUTOTUNER_VARIABLES)"; exit 1; }
	@test -f "$(AUTOTUNER_DESIGN_CONFIG)" || { echo "ERROR: ORFS design config not found: $(AUTOTUNER_DESIGN_CONFIG)"; exit 1; }
	@"$(AUTOTUNER_PYTHON)" -c "import autotuner.distributed"

autotuner-run: check-autotuner
	@test -n "$(AUTOTUNER_MODE)" || { echo "ERROR: use autotuner-sweep or autotuner-tune"; exit 2; }
	cd "$(AUTOTUNER_DIR)" && "$(AUTOTUNER_PYTHON)" -m autotuner.distributed \
		--design "$(AUTOTUNER_DESIGN)" \
		--platform "$(AUTOTUNER_PLATFORM)" \
		--config "$(AUTOTUNER_CONFIG)" \
		--design-config "$(AUTOTUNER_DESIGN_CONFIG)" \
		--variables-file "$(AUTOTUNER_VARIABLES)" \
		--work-dir "$(AUTOTUNER_WORK_HOME)" \
		--experiment "$(AUTOTUNER_EXPERIMENT)" \
		--jobs "$(AUTOTUNER_JOBS)" \
		--openroad_threads "$(AUTOTUNER_THREADS)" \
		--stop_stage "$(AUTOTUNER_STOP_STAGE)" \
		$(AUTOTUNER_MODE) $(AUTOTUNER_EXTRA_ARGS)

autotuner-sweep: AUTOTUNER_MODE := sweep
autotuner-sweep: autotuner-run

autotuner-tune: AUTOTUNER_MODE := tune
autotuner-tune: autotuner-run

.PHONY: help
help:
	@printf '%s\n' \
		'Physical design:' \
		'  make synth|floorplan|place|cts|grt|route|finish|all' \
		'  make gui GUI_STAGE=<orfs_stage>' \
		'  make gui GUI_STAGE=3_1_place_gp_skip_io' \
		'  make gui-grt-failed' \
		'  make gui-synth|gui-floorplan|gui-place|gui-cts|gui-grt|gui-route|gui-final' \
		'' \
		'Configuration:' \
		'  DESIGN_CONFIG=config/orfs_config/sys_top/sys_top.mk' \
		'  FLOW_VARIANT=base' \
		'  WORK_HOME=build/orfs' \
		'' \
		'Verification:' \
		'  make test-all' \
		'  make test-pe|test-systolic|test-postproc|test-top' \
		'  make test-async-fifo|test-mem-arb|test-mem-cdc|test-res-wr' \
		'  make test-sram-wrap-64|test-sram-wrap-256' \
		'  make lint' \
		'' \
		'Cleanup:' \
		'  make clean       (simulation products)' \
		'  make clean-orfs  (ORFS generated products)' \
		'' \
		'AutoTuner:' \
		'  make autotuner-sweep' \
		'  make autotuner-tune AUTOTUNER_EXTRA_ARGS="--algorithm random --samples 20"' \
		'  AUTOTUNER_DESIGN=pe AUTOTUNER_STOP_STAGE=place'
