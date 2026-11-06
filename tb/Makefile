# tb/Makefile
# Re-exec outside nix-shell to avoid host/Nix ABI conflicts with cocotb
_TB_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))

ifdef IN_NIX_SHELL
ifndef HOST_SIM_ENV
_GOALS := $(if $(MAKECMDGOALS),$(MAKECMDGOALS),sim)
.PHONY: $(_GOALS)
$(_GOALS):
	@$(_TB_DIR)/with_host_env.sh $(MAKE) -C $(_TB_DIR) HOST_SIM_ENV=1 $(_GOALS) $(MAKEOVERRIDES)
.DEFAULT_GOAL := sim
else
include $(_TB_DIR)/Makefile.host
endif
else
include $(_TB_DIR)/Makefile.host
endif
