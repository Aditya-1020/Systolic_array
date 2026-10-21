
foreach var {
    STA_NETLIST
    STA_SDC
    STA_LIBERTY
    STA_TOP
    STA_REPORT_DIR
} {
    if {![info exists ::env($var)] || $::env($var) eq ""} {
        error "Missing environment variable: $var"
    }
}

set netlist $::env(STA_NETLIST)
set sdc $::env(STA_SDC)
set liberty $::env(STA_LIBERTY)
set top $::env(STA_TOP)
set report_dir $::env(STA_REPORT_DIR)

foreach f [list $netlist $sdc $liberty] {
    if {![file isfile $f]} {
        error "Missing input file: $f"
    }
}

file mkdir $report_dir

read_liberty $liberty

if {[info exists ::env(STA_MACRO_LIBS)] &&
    $::env(STA_MACRO_LIBS) ne ""} {
    foreach lib [split $::env(STA_MACRO_LIBS) ":"] {
        if {![file isfile $lib]} {
            error "Missing macro Liberty: $lib"
        }
        read_liberty $lib
    }
}

read_verilog $netlist
link_design $top
read_sdc $sdc

check_setup -verbose > $report_dir/check_setup.rpt

report_checks \
    -path_delay max \
    -format full_clock_expanded \
    -group_path_count 20 \
    > $report_dir/setup.rpt

report_checks \
    -path_delay min \
    -format full_clock_expanded \
    -group_path_count 20 \
    > $report_dir/hold.rpt

report_checks \
    -unconstrained \
    -format full_clock_expanded \
    > $report_dir/unconstrained.rpt

report_worst_slack -max > $report_dir/worst_setup_slack.rpt
report_worst_slack -min > $report_dir/worst_hold_slack.rpt
report_wns > $report_dir/wns.rpt
report_tns > $report_dir/tns.rpt

puts "STA reports written to $report_dir"
