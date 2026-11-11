.DEFAULT_GOAL := help

PYTHON ?= python3
RUN_TAG ?= base
FLOW := $(PYTHON) -m scripts.flow

.PHONY: help init validate synth floorplan place cts route finish all status inspect test lint

help:
	@printf '%s\n' \
	  'Setup: make init | validate' \
	  'ORFS:  make synth|floorplan|place|cts|route|finish|all RUN_TAG=baseline' \
	  'Runs:  make status [RUN_TAG=baseline] | make inspect RUN_TAG=baseline' \
	  'RTL:   make test | lint'

init:
	$(FLOW) init

validate:
	$(FLOW) validate

synth floorplan place cts route finish all:
	$(FLOW) run $@ --tag "$(RUN_TAG)"

status:
	$(FLOW) status $(if $(RUN_TAG),--tag "$(RUN_TAG)",)

inspect:
	$(FLOW) inspect --tag "$(RUN_TAG)"

test:
	$(MAKE) -C tb test-all

lint:
	$(MAKE) -C tb lint
