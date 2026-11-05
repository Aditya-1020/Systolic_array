# sta.tcl -- STA of any ORFS stage, read straight from the run directory.
#
#   make sta                      latest stage found in orfs-out
#   make sta STAGE=place          synth|floorplan|place|cts|route|final or an exact name (3_3_place_gp)
#   make sta-shell STAGE=cts      same, then stay in the openroad shell
#   make sta-all                  every stage that has an ODB
#
# Run by hand:  WORK_HOME=orfs-out/sky130hd/default ORFS_FLOW=... openroad -no_splash -exit scripts/sta.tcl
#
# Everything is found from WORK_HOME: results/<platform>/<design>/base/<stage>.{odb,sdc,spef}.
# Reports go to  <WORK_HOME>/reports/<platform>/<design>/base/sta/<stage>/
#
# Environment (empty = default)
#   WORK_HOME        orfs-out/<config>/<tag>; the Makefile sets it from RUN_TAG (make sta RUN_TAG=area_opt).
#                    Without it: ORFS_OUT (default orfs-out) / CONFIG_NAME / RUN_TAG (default 'default')
#   ORFS_FLOW        flow dir of OpenROAD-flow-scripts (platform liberty + setRC.tcl); not needed if
#                    STA_LIBERTY and STA_RC_TCL are both set
#   STAGE            latest (default) | synth | floorplan | place | cts | route | final | <exact stage>
#   STA_MACRO_LIBS   macro liberty files, space or colon separated
#   STA_LIBERTY      std-cell liberty (default: platform tt corner)
#   STA_RC_TCL       RC script (default: <platform>/setRC.tcl)
#   STA_SDC          constraints (default: <stage>.sdc, else the newest earlier stage SDC)
#   STA_PARASITICS   auto (default) | none | placement | grt | spef
#   STA_PROPAGATED   auto (default: from CTS on) | 0 | 1
#   STA_PATHS        full paths per setup/hold report (default 3)
#   STA_ENDPOINTS    endpoints per path group in the endpoint lists (default 20)
#   STA_SLACK_MARGIN violator threshold, ns (default 0.0; 0.2 also lists near-critical paths)
#   STA_FROM / STA_TO / STA_THROUGH   extra path report; ports, pins or instances, space separated
#   STA_POWER        1 to add a vectorless power report (default 0)
#   STA_EXTRA_TCL    file sourced after the design is loaded (extra constraints / overrides)
#   PLATFORM, DESIGN_NICKNAME   only to pick one when results/ holds several runs

proc cfg {name default} {
    if {[info exists ::env($name)] && [string trim $::env($name)] ne ""} {
        return [string trim $::env($name)]
    }
    return $default
}

proc die {msg} {
    puts stderr "sta.tcl: $msg"
    exit 1
}

# ---------------------------------------------------------------- locate run
# run dir: WORK_HOME, or ORFS_OUT/CONFIG_NAME/RUN_TAG (what the Makefile builds from RUN_TAG)
set WORK_HOME [cfg WORK_HOME ""]
if {$WORK_HOME eq ""} {
    set WORK_HOME [file join [cfg ORFS_OUT orfs-out] [cfg CONFIG_NAME ""] [cfg RUN_TAG default]]
}
if {![file isdirectory $WORK_HOME]} { die "run directory not found: $WORK_HOME (set RUN_TAG / CONFIG_NAME or WORK_HOME)" }
set RUN_TAG [cfg RUN_TAG [file tail $WORK_HOME]]

set bases [glob -nocomplain -type d [file join $WORK_HOME results * * base]]
set want_plat [cfg PLATFORM ""]
set want_nick [cfg DESIGN_NICKNAME ""]
set sel {}
foreach b $bases {
    set parts [file split $b]
    set p [lindex $parts end-2]
    set n [lindex $parts end-1]
    if {($want_plat ne "" && $p ne $want_plat) || ($want_nick ne "" && $n ne $want_nick)} continue
    lappend sel $b
}
if {[llength $sel] == 0} { die "no results/<platform>/<design>/base under $WORK_HOME" }
if {[llength $sel] > 1} { die "several runs under $WORK_HOME, set PLATFORM / DESIGN_NICKNAME:\n  [join $sel \n\ \ ]" }

set RESULTS [lindex $sel 0]
set parts   [file split $RESULTS]
set PLATFORM [lindex $parts end-2]
set NICK     [lindex $parts end-1]
set REPORTS  [file join $WORK_HOME reports $PLATFORM $NICK base]

# ---------------------------------------------------------------- stage
set canon {1_synth 2_floorplan 3_place 4_cts 5_route 6_final}
array set alias {synth 1_synth floorplan 2_floorplan place 3_place cts 4_cts route 5_route final 6_final}

proc odb_of {stage} { return [file join $::RESULTS $stage.odb] }

set req [string tolower [cfg STAGE latest]]
if {$req eq "latest"} {
    set stage ""
    foreach s [lreverse $canon] {
        if {[file exists [odb_of $s]]} { set stage $s; break }
    }
} elseif {[info exists alias($req)]} {
    set stage $alias($req)
} else {
    set stage [file rootname $req]
}
if {$stage eq "" || ![file exists [odb_of $stage]]} {
    set have {}
    foreach f [lsort -dictionary [glob -nocomplain -tails -directory $RESULTS *.odb]] { lappend have [file rootname $f] }
    die "no ODB for stage '$req' in $RESULTS\n  available: $have"
}
set ODB [odb_of $stage]
if {![regexp {^([0-9])_} $stage -> major]} { die "cannot read stage number from '$stage'" }

# ---------------------------------------------------------------- inputs
set LIBERTY [cfg STA_LIBERTY ""]
set RC_TCL  [cfg STA_RC_TCL ""]
if {$LIBERTY eq "" || $RC_TCL eq ""} {
    set flow [cfg ORFS_FLOW ""]
    if {$flow eq ""} { die "set ORFS_FLOW (or both STA_LIBERTY and STA_RC_TCL)" }
    set pdir [file join $flow platforms $PLATFORM]
    if {$LIBERTY eq ""} {
        array set deflib {
            sky130hd  lib/sky130_fd_sc_hd__tt_025C_1v80.lib
            nangate45 lib/NangateOpenCellLibrary_typical.lib
        }
        if {[info exists deflib($PLATFORM)]} {
            set LIBERTY [file join $pdir $deflib($PLATFORM)]
        } else {
            set LIBERTY [lindex [lsort [glob -nocomplain [file join $pdir lib *.lib]]] 0]
        }
    }
    if {$RC_TCL eq ""} { set RC_TCL [file join $pdir setRC.tcl] }
}
set MACRO_LIBS [split [string map {: { }} [cfg STA_MACRO_LIBS ""]]]
set libs [list $LIBERTY]
foreach m $MACRO_LIBS { if {$m ne ""} { lappend libs $m } }
foreach f [concat $libs [list $RC_TCL]] {
    if {![file exists $f]} { die "file not found: $f" }
}

# SDC: this stage's, else the newest one from an earlier stage, else STA_SDC
set SDC [cfg STA_SDC ""]
if {$SDC eq ""} {
    foreach c [lsort -dictionary [glob -nocomplain -directory $RESULTS *.sdc]] {
        set key [file rootname [file tail $c]]
        if {[lindex [lsort -dictionary [list $key $stage]] 0] eq $key} { set SDC $c }
    }
}
if {$SDC eq "" || ![file exists $SDC]} { die "no SDC found for $stage; set STA_SDC" }

# ---------------------------------------------------------------- load
foreach l $libs { read_liberty $l }
read_db $ODB
read_sdc $SDC
source $RC_TCL
set extra [cfg STA_EXTRA_TCL ""]
if {$extra ne ""} { source $extra }

set par [string tolower [cfg STA_PARASITICS auto]]
if {$par eq "auto"} {
    set spef [lindex [lsort [glob -nocomplain -directory $RESULTS 6_final*.spef]] 0]
    if {$stage eq "6_final" && $spef ne ""} {
        set par spef
    } elseif {$major >= 5} {
        set have_routes 0
        if {[llength [info commands grt::have_routes]] > 0} { set have_routes [grt::have_routes] }
        set par [expr {$have_routes ? "grt" : "placement"}]
    } elseif {$major >= 3} {
        set par placement
    } else {
        set par none
    }
}
switch $par {
    spef {
        if {![info exists spef] || $spef eq ""} { set spef [lindex [lsort [glob -nocomplain -directory $RESULTS *.spef]] 0] }
        if {$spef eq ""} { die "STA_PARASITICS=spef but no SPEF in $RESULTS" }
        read_spef $spef
        set par_desc "extracted SPEF ([file tail $spef])"
    }
    grt       { estimate_parasitics -global_routing; set par_desc "global-route estimate" }
    placement { estimate_parasitics -placement;      set par_desc "placement estimate" }
    none      { set par_desc "none (wire load only; synthesis-level timing)" }
    default   { die "STA_PARASITICS must be auto|none|placement|grt|spef" }
}

set prop [string tolower [cfg STA_PROPAGATED auto]]
if {$prop eq "auto"} { set prop [expr {$major >= 4}] }
if {$prop} { set_propagated_clock [all_clocks] }
set clk_desc [expr {$prop ? "propagated" : "ideal"}]

# ---------------------------------------------------------------- config
set OUT [file join $REPORTS sta $stage]
file mkdir $OUT

set PATHS     [cfg STA_PATHS 3]
set ENDPOINTS [cfg STA_ENDPOINTS 20]
set MARGIN    [cfg STA_SLACK_MARGIN 0.0]
set FMT       [expr {$prop ? "full_clock_expanded" : "full"}]
set FIELDS    {fanout slew cap}

proc rpt {file title body} {
    set hdr "# $title\n# stage $::stage | $::par_desc | clocks $::clk_desc | margin $::MARGIN ns\n\n"
    sta::redirect_string_begin
    set rc [catch {uplevel 1 $body} err]
    set text [sta::redirect_string_end]
    if {$rc} { append text "\n(skipped: $err)\n" }
    set fh [open [file join $::OUT $file] w]
    puts -nonewline $fh "$hdr$text"
    close $fh
    return $text
}

# run one report command; a failure only skips that command, not the whole file
proc safe {script} {
    if {[catch {uplevel 1 $script} e]} { puts "(skipped: $e)" }
}

proc objs {names} {
    set out {}
    foreach n $names {
        set o [get_ports -quiet $n]
        if {[llength $o] == 0} { set o [get_pins -quiet $n] }
        if {[llength $o] == 0} { set o [get_cells -quiet $n] }
        if {[llength $o] == 0} { error "no port/pin/instance '$n'" }
        lappend out {*}$o
    }
    return $out
}

# ---------------------------------------------------------------- design facts
set macros {}
foreach inst [[ord::get_db_block] getInsts] {
    if {[[$inst getMaster] isBlock]} { lappend macros [$inst getName] }
}
set regs_ck [all_registers -clock_pins]
set regs_d  [all_registers -data_pins]
set ins     [all_inputs]
foreach c [all_clocks] { foreach p [get_property $c sources] { set ins [lsearch -inline -all -not -exact $ins $p] } }
set outs    [all_outputs]

# ---------------------------------------------------------------- reports
set meta [open [file join $OUT analysis.rpt] w]
puts $meta "design      $NICK ($PLATFORM), run $RUN_TAG"
puts $meta "stage       $stage"
puts $meta "odb         $ODB"
puts $meta "sdc         $SDC"
puts $meta "liberty     [join $libs {, }]"
puts $meta "parasitics  $par_desc"
puts $meta "clocks      $clk_desc"
puts $meta "macros      [llength $macros] ([join $macros {, }])"
close $meta

rpt check_setup.rpt "unconstrained / unlinked / loops" { check_setup -verbose }

set summary [rpt summary.rpt "timing summary" {
    puts "--- setup ---"
    report_worst_slack -max -digits 3
    report_wns -digits 3
    report_tns -digits 3
    puts "\n--- hold ---"
    report_worst_slack -min -digits 3
    puts "\n--- clocks ---"
    safe { report_clock_min_period }
    safe { report_clock_min_period -include_port_paths }
    puts "\n--- area ---"
    safe { report_design_area }
}]

rpt clocks.rpt "clock properties, skew, latency" {
    report_clock_properties
    if {$::prop} {
        puts "\n--- skew (setup) ---"
        safe { report_clock_skew -setup }
        puts "\n--- skew (hold) ---"
        safe { report_clock_skew -hold }
        puts "\n--- latency ---"
        safe { report_clock_latency }
    } else {
        puts "\nideal clocks: skew and latency are not meaningful before CTS"
    }
}

rpt endpoints.rpt "worst endpoints per path group" {
    puts "=== setup ==="
    report_checks -path_delay max -group_path_count $::ENDPOINTS -format end
    puts "\n=== hold ==="
    report_checks -path_delay min -group_path_count $::ENDPOINTS -format end
}

rpt violations.rpt "paths with slack <= margin" {
    puts "=== setup ==="
    report_checks -path_delay max -slack_max $::MARGIN -group_path_count 5000 -format end
    puts "\n=== hold ==="
    report_checks -path_delay min -slack_max $::MARGIN -group_path_count 5000 -format end
}

rpt paths.rpt "worst paths" {
    puts "=== setup ==="
    report_checks -path_delay max -group_path_count $::PATHS -fields $::FIELDS -digits 3 -format $::FMT
    puts "\n=== hold ==="
    report_checks -path_delay min -group_path_count $::PATHS -fields $::FIELDS -digits 3 -format $::FMT
}

rpt groups.rpt "worst setup path by category" {
    if {[llength $::regs_ck] && [llength $::regs_d]} {
        puts "=== reg -> reg ==="
        report_checks -path_delay max -from $::regs_ck -to $::regs_d -digits 3 -fields $::FIELDS
    }
    if {[llength $::ins] && [llength $::regs_d]} {
        puts "\n=== input -> reg ==="
        report_checks -path_delay max -from $::ins -to $::regs_d -digits 3 -fields $::FIELDS
    }
    if {[llength $::regs_ck] && [llength $::outs]} {
        puts "\n=== reg -> output ==="
        report_checks -path_delay max -from $::regs_ck -to $::outs -digits 3 -fields $::FIELDS
    }
    if {[llength $::ins] && [llength $::outs]} {
        puts "\n=== input -> output (combinational) ==="
        report_checks -path_delay max -from $::ins -to $::outs -digits 3 -fields $::FIELDS
    }
}

if {[llength $macros] > 0} {
    rpt macros.rpt "paths through memory macros" {
        foreach m $::macros {
            puts "=== $m: setup ==="
            report_checks -path_delay max -through [get_cells $m] -digits 3 -fields $::FIELDS
            puts "\n=== $m: hold ==="
            report_checks -path_delay min -through [get_cells $m] -digits 3 -fields $::FIELDS
        }
    }
}

rpt electrical.rpt "slew / capacitance / fanout violations" {
    report_check_types -max_slew -max_capacitance -max_fanout -violators
}

rpt design.rpt "area, cells, logic depth" {
    safe { report_design_area }
    safe { report_cell_usage }
    safe { report_logic_depth_histogram }
}

if {[cfg STA_POWER 0]} {
    rpt power.rpt "power (vectorless)" { report_power }
}

set from [cfg STA_FROM ""]
set to   [cfg STA_TO ""]
set thr  [cfg STA_THROUGH ""]
if {$from ne "" || $to ne "" || $thr ne ""} {
    rpt custom.rpt "custom: from '$from' through '$thr' to '$to'" {
        set a {}
        if {$::from ne ""} { lappend a -from    [objs $::from] }
        if {$::thr  ne ""} { lappend a -through [objs $::thr] }
        if {$::to   ne ""} { lappend a -to      [objs $::to] }
        report_checks -path_delay max -group_path_count $::PATHS -digits 3 -fields $::FIELDS -format $::FMT {*}$a
        puts "\n=== hold ==="
        report_checks -path_delay min -group_path_count $::PATHS -digits 3 -fields $::FIELDS -format $::FMT {*}$a
    }
}

if {$par eq "spef"} {
    rpt parasitics.rpt "annotation coverage" { report_parasitic_annotation }
}

puts "design $NICK | run $RUN_TAG | $stage | $par_desc | clocks $clk_desc"
puts $summary
puts "reports: $OUT"