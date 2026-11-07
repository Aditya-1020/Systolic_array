current_design sys_top

set clk_core_period 5.000
# set clk_core_period 3.333
set clk_apb_div 2
set clk_apb_period [expr {$clk_core_period * $clk_apb_div}]

set clk_core_name clk_core
set clk_apb_name clk_apb

set clk_port i_clk
set rst_port i_arst_n

create_clock -name $clk_core_name -period $clk_core_period [get_ports $clk_port]
create_generated_clock -name $clk_apb_name -source [get_ports $clk_port] -divide_by $clk_apb_div [get_nets clk_apb]


# assumptions
set io_in_frac  0.20
set io_out_frac 0.20

set io_in_max  [expr {$clk_apb_period * $io_in_frac}]
set io_out_max [expr {$clk_apb_period * $io_out_frac}]

set io_min 0.0

set unc_setup 0.25
set unc_hold  0.10

set clk_tran 0.10

set drv_cell sky130_fd_sc_hd__buf_2
set drv_pin  X
set out_load 0.05
set max_tran 1.0


set_clock_uncertainty -setup $unc_setup [get_clocks $clk_core_name]
set_clock_uncertainty -hold  $unc_hold  [get_clocks $clk_core_name]

set_clock_uncertainty -setup $unc_setup [get_clocks $clk_apb_name]
set_clock_uncertainty -hold  $unc_hold  [get_clocks $clk_apb_name]

set_clock_transition $clk_tran [get_clocks $clk_core_name]
set_clock_transition $clk_tran [get_clocks $clk_apb_name]


set clk_ports [get_ports $clk_port]
set rst_ports [get_ports $rst_port]

set apb_out_ports [all_outputs]
set apb_in_ports  {}

# external inputs except clocks and asynchronous reset
foreach p [all_inputs -no_clocks] {
    if {[get_property $p name] ne $rst_port} {
        lappend apb_in_ports $p
    }
}

set_input_delay -clock $clk_apb_name -max $io_in_max $apb_in_ports
set_input_delay -clock $clk_apb_name -min $io_min $apb_in_ports

set_driving_cell -lib_cell $drv_cell -pin $drv_pin $apb_in_ports

set_output_delay -clock $clk_apb_name -max $io_out_max $apb_out_ports
set_output_delay -clock $clk_apb_name -min $io_min $apb_out_ports

set_load $out_load $apb_out_ports


# reset synchronizer flops
set rst_sync_flops [get_cells -quiet {
    u_reset_sync_core.sync_q*_DFF*
    u_reset_sync_apb.sync_q*_DFF*
    u_reset_sync_apb_csr.sync_q*_DFF*
}]

if {[llength $rst_sync_flops] == 0} {
    set rst_sync_flops \
        [get_cells -hierarchical -quiet *reset_sync*sync_q*]
}

if {[llength $rst_sync_flops] == 0} {
    error "Reset synchronizer flops not found. Update reset synchronizer hierarchy."
}

# external asynchronous reset to reset synchronizer
set_false_path -from $rst_ports -to $rst_sync_flops


# sync reset distribution
set rst_tree_core [expr {2.0 * $clk_core_period}]
set rst_tree_apb  [expr {2.0 * $clk_apb_period}]

# Core reset
if {![catch {
    all_registers -clock $clk_core_name -async_pins
} core_arst_pins]} {

    set core_rst_source \
        [get_pins -quiet u_reset_sync_core/sync_q*/Q]

    if {[llength $core_arst_pins] > 0 &&
        [llength $core_rst_source] > 0} {

        set_max_delay $rst_tree_core \
            -from $core_rst_source \
            -to $core_arst_pins
    }
}

# APB-domain reset distribution
if {![catch {
    all_registers -clock $clk_apb_name -async_pins
} apb_arst_pins]} {

    set apb_rst_source \
        [get_pins -quiet u_reset_sync_apb/sync_q*/Q]

    set apb_csr_rst_source \
        [get_pins -quiet u_reset_sync_apb_csr/sync_q*/Q]

    if {[llength $apb_arst_pins] > 0} {

        if {[llength $apb_rst_source] > 0} {
            set_max_delay $rst_tree_apb \
                -from $apb_rst_source \
                -to $apb_arst_pins
        }

        if {[llength $apb_csr_rst_source] > 0} {
            set_max_delay $rst_tree_apb \
                -from $apb_csr_rst_source \
                -to $apb_arst_pins
        }
    }
}


set_max_transition $max_tran [current_design]
