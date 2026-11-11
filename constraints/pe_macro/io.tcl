# pe macro arcitectural pin placement
# activation flows horizontally
# weight and partial sum flow vertically

proc bus_pins {base width} {
    set pins {}
    for {set bit 0} {$bit < $width} {incr bit} {
        lappend pins [format {%s[%d]} $base $bit]
    }
    return $pins
}

# activation input: left edge
set_io_pin_constraint -pin_names [bus_pins i_a 8] -region left:* -group -order

# activation output: right edge
set_io_pin_constraint -pin_names [bus_pins o_a 8] -region right:* -group -order

# weight and partial-sum inputs: top edge
set_io_pin_constraint -pin_names [concat [bus_pins i_w 8] [bus_pins i_psum 19] {i_clk_w i_clk_adv}] -region top:* -group -order

# weight and partial-sum outputs: bottom edge
set_io_pin_constraint -pin_names [concat [bus_pins o_w 8] [bus_pins o_psum 19]] -region bottom:* -group -order