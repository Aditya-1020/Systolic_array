ORFS_FLOW ?= $(HOME)/eda/orfs-nix/OpenROAD-flow-scripts/flow
WORK_HOME := $(CURDIR)/orfs-out

PLATFORM := sky130hd
DESIGN_NICKNAME := sys
DESIGN_TOP := systolic_top
FLOW_VARIANT ?= icg
CORNER ?= tt_025C_1v80

ORFS = $(MAKE) -C $(ORFS_FLOW) \
	DESIGN_CONFIG=$(CURDIR)/design-configs/config.mk \
	WORK_HOME=$(WORK_HOME) \
	FLOW_VARIANT=$(FLOW_VARIANT)

# post-synth STA
RESULTS_DIR := $(WORK_HOME)/results/$(PLATFORM)/$(DESIGN_NICKNAME)/$(FLOW_VARIANT)
REPORT_DIR := $(WORK_HOME)/reports/$(PLATFORM)/$(DESIGN_NICKNAME)/$(FLOW_VARIANT)/sta/$(CORNER)

STA_NETLIST := $(RESULTS_DIR)/1_2_yosys.v
STA_SDC := $(RESULTS_DIR)/1_2_yosys.sdc
STA_LIBERTY := $(ORFS_FLOW)/platforms/$(PLATFORM)/lib/sky130_fd_sc_hd__$(CORNER).lib
STA_MACRO_LIBS := $(CURDIR)/fakeram/fakeram130_128x64/fakeram130_128x64.lib
STA_SCRIPT := $(CURDIR)/scripts/sta_post_synth.tcl

STA_ENV = STA_NETLIST=$(STA_NETLIST) STA_SDC=$(STA_SDC) STA_LIBERTY=$(STA_LIBERTY) \
		STA_MACRO_LIBS=$(STA_MACRO_LIBS) STA_TOP=$(DESIGN_TOP) STA_REPORT_DIR=$(REPORT_DIR)

.PHONY: orfs orfs-% clean-orfs sta sta-shell

orfs:
	$(ORFS)

orfs-%:
	$(ORFS) $*

clean-orfs:
	rm -rf $(WORK_HOME)

sta:
	mkdir -p $(REPORT_DIR)
	$(STA_ENV) sta -no_splash -exit $(STA_SCRIPT)

sta-shell:
	mkdir -p $(REPORT_DIR)
	$(STA_ENV) sta -no_splash $(STA_SCRIPT)
