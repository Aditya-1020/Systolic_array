
set out_dir $::env(REPORTS_DIR)
file mkdir $out_dir
set out [file join $out_dir insert_summary.rpt]

set f [open $out w]
puts $f "design: $::env(DESIGN_NAME)"
puts $f "platform: $::env(PLATFORM)"

if {[info exists ::env(RESULTS_DIR)]} {
	puts $f "results: $::env(RESULTS_DIR)"
}

close $f

if {[llength [info commands report_design_area]] > 0} {
	redirect -append $out {
		report_design_area
	}
} else {
	set f [open $out a]
	puts $f "report_design_area is not available in this step"
	close $f
}

puts "Wrote $out"
