# top levl pin constraints
# apb address/control enter from the left, write data from the bottom
# read data and response signals leave from the right

proc bus_pins {base width} {
    set pins {}
    for {set bit 0} {$bit < $width} {incr bit} {
        lappend pins [format {%s[%d]} $base $bit]
    }
    return $pins
}

set_io_pin_constraint -pin_names {i_clk_core i_clk_apb i_arst_n} -region top:* -group -order
set_io_pin_constraint -pin_names {i_psel i_penable i_pwrite} -region top:* -group -order

set APB_ADDR_CTRL_PINS [concat [bus_pins i_paddr 14] [bus_pins i_pprot 3] [bus_pins i_pstrb 4]]

set_io_pin_constraint -pin_names $APB_ADDR_CTRL_PINS -region left:* -group -order

set_io_pin_constraint -pin_names [bus_pins i_pwdata 32] -region bottom:* -group -order
set_io_pin_constraint -pin_names [bus_pins o_prdata 32] -region right:* -group -order

set_io_pin_constraint -pin_names {o_pready o_pslverr o_irq} -region right:* -group -order
