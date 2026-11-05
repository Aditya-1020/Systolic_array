# Usage:
# source scripts/inspect_inst.tcl
# inspect_inst _60776_

proc inspect_inst {inst_name} {
    set block [ord::get_db_block]
    set inst [$block findInst $inst_name]

    if {$inst == "NULL"} {
        puts "ERROR: Instance $inst_name not found"
        return
    }

    puts "\n================================"
    puts "Instance: [$inst getName]"
    puts "Master:   [[$inst getMaster] getName]"
    puts "================================"

    foreach iterm [$inst getITerms] {
        set mterm [$iterm getMTerm]
        set net [$iterm getNet]

        if {$net != "NULL"} {
            puts "[format %-8s [$mterm getName]] -> [$net getName]"
        } else {
            puts "[format %-8s [$mterm getName]] -> UNCONNECTED"
        }
    }
}