EDA_HOME ?= $(HOME)/.eda
ORFS_DIR := $(EDA_HOME)/orfs-nix/OpenROAD-flow-scripts
FLOW_DIR := $(ORFS_DIR)/flow
DESIGN_CONFIG := $(CURDIR)/design-configs/config.mk
WORK_HOME := $(CURDIR)/orfs-out
VARIANT ?= icg

ORFS = $(MAKE) -C $(FLOW_DIR) \
		DESIGN_CONFIG=$(DESIGN_CONFIG) \
		WORK_HOME=$(WORK_HOME) \
		VARIANT=$(VARIANT)

.PHONY: orfs clean-orfs

orfs:
	$(ORFS)

orfs-%: # make orfs* synth, floorplan, place, route, cts
	$(ORFS) $*

clean-orfs:
	rm -rf $(WORK_HOME)
