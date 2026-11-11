.DEFAULT_GOAL := help

ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
TB_MAKE := $(MAKE) --no-print-directory -C $(ROOT)/tb

ORFS_FLOW ?= $(HOME)/eda/orfs-nix/OpenROAD-flow-scripts/flow

DESIGN_CONFIG ?= $(ROOT)/config/orfs_config/sys_top.mk

FLOW_VARIANT ?= base
WORK_HOME ?= $(ROOT)/build/orfs

# ORFS_MAKE = $(MAKE) --no-print-directory -C "$(ORFS_FLOW)" DESIGN_CONFIG="$(DESIGN_CONFIG)" FLOW_VARIANT="$(FLOW_VARIANT)" WORK_HOME="$(WORK_HOME)"
ORFS_MAKE = $(MAKE) --no-print-directory -C "$(ORFS_FLOW)" DESIGN_CONFIG="$(abspath $(DESIGN_CONFIG))" FLOW_VARIANT="$(FLOW_VARIANT)" WORK_HOME="$(abspath $(WORK_HOME))"

.PHONY: check-orfs
check-orfs:
	@test -f "$(ORFS_FLOW)/Makefile" || { echo "ERROR: ORFS Makefile not found: $(ORFS_FLOW)/Makefile"; exit 1; }
	@test -f "$(DESIGN_CONFIG)" || { echo "ERROR: Design config not found: $(DESIGN_CONFIG)"; exit 1; }

.PHONY: synth floorplan place cts grt route finish all

synth floorplan place cts grt route finish all: check-orfs
	$(ORFS_MAKE) $@


.PHONY: gui-synth gui-floorplan gui-place gui-cts gui-grt gui-route gui-final

gui-synth gui-floorplan gui-place gui-cts gui-grt gui-route gui-final: check-orfs
	$(ORFS_MAKE) gui_$(patsubst gui-%,%,$@)

.PHONY: gui
gui: check-orfs
	@test -n "$(GUI_STAGE)" || { echo "Usage: make gui GUI_STAGE=<ORFS GUI target>"; exit 2; }
	$(ORFS_MAKE) gui_$(GUI_STAGE)

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

.PHONY: help
help:
	@printf '%s\n' \
		'Physical design:' \
		'  make synth|floorplan|place|cts|grt|route|finish|all' \
		'  make gui GUI_STAGE=<stage>' \
		'  make gui-synth|gui-floorplan|gui-place|gui-cts|gui-grt|gui-route|gui-final' \
		'' \
		'Configuration:' \
		'  DESIGN_CONFIG=config/orfs_config/sys_top.mk' \
		'  DESIGN_CONFIG=config/orfs_config/accelerator.mk' \
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
		'  make clean-orfs  (ORFS generated products)'