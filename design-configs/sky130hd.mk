# Sky130HD ORFS adapter; shared project integration lives in orfs.mk.
include $(dir $(lastword $(MAKEFILE_LIST)))orfs.mk
