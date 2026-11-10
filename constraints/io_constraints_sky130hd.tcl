# Clock and reset
set_io_pin_constraint -pin_names {i_clk i_arst_n} -region top:* -group -order

# APB control
set_io_pin_constraint -pin_names {i_psel i_penable i_pwrite} -region top:* -group -order

# APB address
set_io_pin_constraint -pin_names {i_paddr[0] i_paddr[1] i_paddr[2] i_paddr[3] i_paddr[4] i_paddr[5] i_paddr[6] i_paddr[7] \
                i_paddr[8] i_paddr[9] i_paddr[10] i_paddr[11] i_paddr[12] i_paddr[13] \
                i_pprot[0] i_pprot[1] i_pprot[2] i_pstrb[0] i_pstrb[1] i_pstrb[2] i_pstrb[3]} \
    -region left:* -group -order

# APB write data
set_io_pin_constraint \
    -pin_names {i_pwdata[0] i_pwdata[1] i_pwdata[2] i_pwdata[3] i_pwdata[4] i_pwdata[5] i_pwdata[6] i_pwdata[7] \
                i_pwdata[8] i_pwdata[9] i_pwdata[10] i_pwdata[11] i_pwdata[12] i_pwdata[13] i_pwdata[14] i_pwdata[15]} \
    -region bottom:* -group -order

set_io_pin_constraint \
    -pin_names {i_pwdata[16] i_pwdata[17] i_pwdata[18] i_pwdata[19] i_pwdata[20] i_pwdata[21] i_pwdata[22] i_pwdata[23] \
                i_pwdata[24] i_pwdata[25] i_pwdata[26] i_pwdata[27] i_pwdata[28] i_pwdata[29] i_pwdata[30] i_pwdata[31]} \
    -region bottom:* -group -order

# APB read data
set_io_pin_constraint \
    -pin_names {o_prdata[0] o_prdata[1] o_prdata[2] o_prdata[3] o_prdata[4] o_prdata[5] o_prdata[6] o_prdata[7] \
                o_prdata[8] o_prdata[9] o_prdata[10] o_prdata[11] o_prdata[12] o_prdata[13] o_prdata[14] o_prdata[15] \
                o_prdata[16] o_prdata[17] o_prdata[18] o_prdata[19] o_prdata[20] o_prdata[21] o_prdata[22] o_prdata[23] \
                o_prdata[24] o_prdata[25] o_prdata[26] o_prdata[27] o_prdata[28] o_prdata[29] o_prdata[30] o_prdata[31]} \
    -region right:* -group -order

# APB response and interrupt
set_io_pin_constraint -pin_names {o_pready o_pslverr o_irq} -region right:* -group -order