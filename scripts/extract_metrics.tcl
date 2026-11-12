# extract reports from a finished orfs run
set odb_file $::env(ODB_FILE)
set sdc_file $::env(SDC_FILE)
set spef_file $::env(SPEF_FILE)
set lib_files $::env(LIB_FILES)
set out_dir $::env(OUT_DIR)

file mkdir $out_dir

# read libraries
foreach lib $lib_files {
    read_liberty $lib
}

# read design
read_db $odb_file
read_sdc $sdc_file

if {$spef_file ne ""} {
    read_spef $spef_file
}

# report helper
proc run_report {out_dir filename args} {
    tee -file "$out_dir/$filename" $args
}

# timing
run_report $out_dir setup.rpt report_checks -path_delay max -format full_clock_expanded
run_report $out_dir hold.rpt report_checks -path_delay min -format full_clock_expanded
run_report $out_dir worst_paths.rpt report_checks -path_delay max -group_path_count 20 -format full_clock_expanded
run_report $out_dir clock_latency.rpt report_clock_latency

# physical
run_report $out_dir cell_usage.rpt report_cell_usage -verbose
run_report $out_dir buffers.rpt report_buffers
run_report $out_dir design_area.rpt report_design_area

# power
run_report $out_dir power.rpt report_power

# logic depth
run_report $out_dir logic_depth.rpt report_logic_depth_histogram -num_bins 20

puts "\nreports generated in $out_dir"
