
# macro_placement.tcl
# Macro size: 191.820 x 329.120 um
# Example spacing: 20 um
# Verify coordinates against DIE_AREA / CORE_AREA.

# Accumulator buffer pair — upper row
place_macro \
    -macro_name {inst_acc_buf.gen_half[0].u_fakeram} \
    -location {100 450} \
    -orientation R0

place_macro \
    -macro_name {inst_acc_buf.gen_half[1].u_fakeram} \
    -location {311.82 450} \
    -orientation R0

# Result buffer pair — lower row
place_macro \
    -macro_name {inst_res_buf.gen_half[0].u_fakeram} \
    -location {100 100} \
    -orientation R0

place_macro \
    -macro_name {inst_res_buf.gen_half[1].u_fakeram} \
    -location {311.82 100} \
    -orientation R0
