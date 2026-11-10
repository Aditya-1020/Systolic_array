.DEFAULT_GOAL := help

PYTHON ?= python3
RUN_TAG ?= base

.PHONY: help synth floorplan place cts route finish all

help:
	@printf '%s\n' \
	  'Physical design:' \
	  '  make synth' \
	  '  make floorplan' \
	  '  make place' \
	  '  make cts' \
	  '  make route' \
	  '  make finish' \
	  '  make all' \
	  'Use RUN_TAG=experiment_name to separate runs.'

synth floorplan place cts route finish all:
	$(PYTHON) scripts/run.py $@ --tag "$(RUN_TAG)"