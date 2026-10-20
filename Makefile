ORFS_DIR := $(EDA_HOME)/orfs-nix/OpenROAD-flow-scripts
ORFS_MAKEFILE := $(ORFS_DIR)/flow/Makefile
DESIGN_CONFIG := $(CURDIR)/design-configs/config.mk

.PHONY: orfs orfs-synth orfs-floorplan

orfs:
	$(MAKE) --file=$(ORFS_MAKEFILE) DESIGN_CONFIG=$(DESIGN_CONFIG)

orfs-synth:
	$(MAKE) --file=$(ORFS_MAKEFILE) DESIGN_CONFIG=$(DESIGN_CONFIG) synth

orfs-floorplan:
	$(MAKE) --file=$(ORFS_MAKEFILE) DESIGN_CONFIG=$(DESIGN_CONFIG) floorplan