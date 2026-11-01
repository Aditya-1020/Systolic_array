foreach v {STA_ODB STA_RESULTS_DIR STA_SDC_FALLBACK STA_LIBERTY STA_RC_TCL STA_REPORT_DIR} {
    if {![info exists ::env($v)] || $::env($v) eq ""} {
        error "missing env var: $v"
    }
}

proc env_or {name} {
    expr {[info exists ::env($name)] ? $::env($name) : ""}
}

foreach path [list $::env(STA_ODB) $::env(STA_LIBERTY) $::env(STA_RC_TCL) $::env(STA_SDC_FALLBACK)] {
    if {![file exists $path]} {
        error "file not found: $path"
    }
}

set results $::env(STA_RESULTS_DIR)
set out $::env(STA_REPORT_DIR)
set odb $::env(STA_ODB)
set stage [file rootname [file tail $odb]]

if {![regexp {^([0-9])_} $stage match major]} {
    error "cannot determine stage from ODB name: $stage"
}

file mkdir $out

set sdc [file join $results "$stage.sdc"]
if {![file exists $sdc]} {
    set exact_sdc $sdc
    set sdc ""
    set sdc_files [glob -nocomplain -directory $results -types f {[1-9]_[1-9_A-Za-z]*.sdc}]
    set sdc_files [lsort -decreasing -dictionary $sdc_files]
    foreach candidate $sdc_files {
        if {[lindex [lsort -decreasing -dictionary [list $candidate $exact_sdc]] 0] eq $exact_sdc} {
            set sdc $candidate
            break
        }
    }
    if {$sdc eq ""} {
        set sdc $::env(STA_SDC_FALLBACK)
    }
}

set libs [list $::env(STA_LIBERTY)]
if {[env_or STA_MACRO_LIBS] ne ""} {
    lappend libs {*}[split $::env(STA_MACRO_LIBS) ":"]
}
foreach lib $libs {
    if {$lib eq ""} {
        continue
    }
    if {![file exists $lib]} {
        error "Liberty not found: $lib"
    }
    read_liberty $lib
}

read_db $odb
read_sdc $sdc
source $::env(STA_RC_TCL)

set parasitics "none"
if {$major >= 4} {
    set_propagated_clock [all_clocks]
}
if {$stage eq "6_final"} {
    set spef [file join $results 6_final.spef]
    if {![file exists $spef]} {
        error "final SPEF not found: $spef"
    }
    read_spef $spef
    set parasitics "extracted SPEF"
} elseif {$major >= 5} {
    set have_routes 0
    if {[llength [info commands grt::have_routes]] > 0} {
        set have_routes [grt::have_routes]
    }
    if {$have_routes} {
        estimate_parasitics -global_routing
        set parasitics "global-route estimate"
    } else {
        estimate_parasitics -placement
        set parasitics "placement estimate"
    }
} elseif {$major >= 3} {
    estimate_parasitics -placement
    set parasitics "placement estimate"
}

set f [open [file join $out analysis.rpt] w]
puts $f "ODB: $odb"
puts $f "SDC: $sdc"
puts $f "Parasitics: $parasitics"
close $f

check_setup -verbose > [file join $out check_setup.rpt]

report_worst_slack -max -digits 3 > [file join $out summary.rpt]
report_wns -max -digits 3 >> [file join $out summary.rpt]
report_tns -max -digits 3 >> [file join $out summary.rpt]
report_worst_slack -min -digits 3 >> [file join $out summary.rpt]
report_wns -min -digits 3 >> [file join $out summary.rpt]
report_tns -min -digits 3 >> [file join $out summary.rpt]

report_check_types -max_slew -max_capacitance -max_fanout -violators \
    > [file join $out electrical_violations.rpt]

proc viol {{type max} {n 5000} args} {
    report_checks -path_delay $type -slack_max 0 -group_path_count $n \
        -format end {*}$args
}
proc vpath {{type max} {n 1} args} {
    report_checks -path_delay $type -slack_max 0 -group_path_count $n \
        -fields {fanout slew cap} -format full_clock_expanded {*}$args
}

viol max 5000 > [file join $out setup_violations.rpt]
viol min 5000 > [file join $out hold_violations.rpt]
vpath max 1 > [file join $out setup_worst_paths.rpt]
vpath min 1 > [file join $out hold_worst_paths.rpt]

if {$stage eq "6_final"} {
    report_parasitic_annotation > [file join $out parasitic_annotation.rpt]
}

puts "Stage: $stage"
puts "SDC: $sdc"
puts "Parasitics: $parasitics"
puts "STA reports: $out"