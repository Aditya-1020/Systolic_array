# pe macro sdc entry point
set _sdc_dir [file dirname [file normalize [info script]]]

source [file join $_sdc_dir clocks.sdc]
source [file join $_sdc_dir io.sdc]
source [file join $_sdc_dir exceptions.sdc]

unset _sdc_dir
