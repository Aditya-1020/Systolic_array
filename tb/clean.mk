TB_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))

.PHONY: clean
clean:
	rm -rf $(TB_DIR)/sim_build_* $(TB_DIR)/__pycache__ $(TB_DIR)/helper/__pycache__
	rm -f $(TB_DIR)/results*.xml $(TB_DIR)/*.vcd $(TB_DIR)/*.fst
