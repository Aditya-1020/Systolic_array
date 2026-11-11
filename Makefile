.DEFAULT_GOAL := help

PYTHON ?= python3
RUN_TAG ?= base
FLOW := $(PYTHON) -m scripts.flow
TB_MAKE = $(MAKE) --no-print-directory -C tb

.PHONY: help init validate synth floorplan place cts route finish all status inspect \
        test test-all test-async-fifo test-pe test-round test-relu test-postproc \
        test-systolic test-sram-wrap-64 test-sram-wrap-256 test-mem-arb \
        test-mem-cdc test-res-wr test-top lint clean
help:
	@printf '%s\n' \
		'Setup:  make init | validate' \
		'ORFS:   make synth|floorplan|place|cts|route|finish|all RUN_TAG=baseline' \
		'Runs:   make status|inspect RUN_TAG=baseline' \
		'Tests:  make test|test-all' \
		'        make test-async-fifo|test-pe|test-round|test-relu|test-postproc' \
		'        make test-systolic|test-sram-wrap-64|test-sram-wrap-256' \
		'        make test-mem-arb|test-mem-cdc|test-res-wr|test-top' \
		'Other:  make lint | clean'

init:
	$(FLOW) init

validate:
	$(FLOW) validate

synth floorplan place cts route finish all:
	$(FLOW) run $@ --tag "$(RUN_TAG)"

status:
	$(FLOW) status --tag "$(RUN_TAG)"

inspect:
	$(FLOW) inspect --tag "$(RUN_TAG)"

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

clean:
	@find . -type d -name '__pycache__' -prune -exec rm -rf {} +
	@rm -rf tb/sim_build_*
	@rm -f tb/results*.xml tb/*.vcd tb/*.fst



# Gui help
.PHONY: gui
# Generic GUI target:
# make gui GUI_STAGE=3_3_place_gp RUN_TAG=baseline
GUI_STAGES := synth floorplan place cts grt route finish final

gui:
	@test -n "$(GUI_STAGE)" || { echo "ERROR: GUI_STAGE is required."; echo "Usage: make gui GUI_STAGE=<stage> RUN_TAG=<tag>"; exit 2; }
	$(PYTHON) -m scripts.flow gui "$(GUI_STAGE)" --tag "$(RUN_TAG)"


define GUI_TARGET
.PHONY: gui_$(1)
gui_$(1):
	$(PYTHON) -m scripts.flow gui $(1) --tag "$(RUN_TAG)"
endef

$(foreach stage,$(GUI_STAGES),$(eval $(call GUI_TARGET,$(stage))))