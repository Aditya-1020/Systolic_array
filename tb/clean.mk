TB_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
TOPLEVEL ?= systolic_array

.PHONY: clean

clean:
	rm -rf $(TB_DIR)/sim_build_$(TOPLEVEL)
	rm -rf $(TB_DIR)/__pycache__ $(TB_DIR)/helper/__pycache__
	rm -f $(TB_DIR)/results.xml