# apb and core clock domains are async
# all crosing through cdc structures in chip (std-cell impl)

set_clock_groups -asynchronous -group [get_clocks $CORE_CLOCK] -group [get_clocks $APB_CLOCK]

# external async reset entry, release is synchronized in each domain with sync
set_false_path -from [get_ports i_arst_n]

set_max_transition 1.000 [current_design]
