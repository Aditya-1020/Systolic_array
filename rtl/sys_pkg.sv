`default_nettype none
package sys_pkg;
    localparam int p_n = 8;
    localparam int p_dw = 8;
    localparam int p_acc_w = 2*p_dw + $clog2(p_n);
    localparam int p_shift_w = $clog2(p_acc_w + 1);

    localparam int p_max_rows = 64;
    localparam int p_beat_w = p_n*p_dw;
    localparam int p_raw_col_w = 32;
    localparam int p_raw_beats = (p_n*p_raw_col_w)/p_beat_w;

    localparam int p_wtiles = 4;
    localparam int p_wbuf_depth = p_wtiles*p_n;
    localparam int p_wbuf_macro_depth = 64;
    localparam int p_abuf_depth = p_max_rows;
    localparam int p_rbuf_depth = p_max_rows*p_raw_beats;

    localparam int p_wbuf_aw = $clog2(p_wbuf_depth);
    localparam int p_wbuf_macro_aw = $clog2(p_wbuf_macro_depth);
    localparam int p_abuf_aw = $clog2(p_abuf_depth);
    localparam int p_rbuf_aw = $clog2(p_rbuf_depth);
    localparam int p_addr_w = 32;

    localparam int p_shift_max = p_acc_w - 1;

    typedef logic [p_beat_w-1:0] beat_t;
    typedef logic [p_addr_w-1:0] addr_t;
    typedef logic signed [p_dw-1:0] data_t;
    typedef logic signed [p_acc_w-1:0] acc_t;

    typedef enum logic {
        MODE_INT8 = 1'b0,
        MODE_RAW = 1'b1
    } output_mode_t;

    typedef enum logic [2:0] {
        ST_IDLE = 3'd0,
        ST_CHECK = 3'd1,
        ST_WLOAD = 3'd2,
        ST_RUN = 3'd3,
        ST_FLUSH = 3'd4,
        ST_DONE = 3'd5
    } ctrl_state_t;
endpackage
`default_nettype wire
