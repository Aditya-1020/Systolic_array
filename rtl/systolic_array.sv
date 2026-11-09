`default_nettype none
module systolic_array #(
    parameter int N = sys_pkg::p_n,
    parameter int DW = sys_pkg::p_dw,
    parameter int ACC_W = sys_pkg::p_acc_w
) (
    input logic i_clk,
    input logic i_rstn,
    input logic i_w_load,
    input logic [N*DW-1:0] i_w_data,
    input logic i_a_advance,
    input logic i_a_valid,
    input logic [N*DW-1:0] i_a_data,
    input logic i_clear,
    output logic o_c_valid,
    output logic [N*ACC_W-1:0] o_c_data
);
localparam int HOP = 7;
localparam int VALID_LAT = HOP * (2 * N - 1);

logic clk_w, clk_adv;
logic [N*DW-1:0] a_skewed;
logic [N*ACC_W-1:0] c_bottom;
logic [VALID_LAT-1:0] valid_q;

OPENROAD_CLKGATE u_cg_weight (.CK(i_clk), .E(i_w_load), .GCK(clk_w));
OPENROAD_CLKGATE u_cg_advance (.CK(i_clk), .E(i_a_advance), .GCK(clk_adv));

genvar r;
generate
    for (r = 0; r < N; r++) begin : g_input_skew
        localparam int SKEW = HOP * r;
        if (SKEW == 0) begin : g_no_delay
            assign a_skewed[r*DW +: DW] = i_a_data[r*DW +: DW];
        end else begin : g_delay
            logic [SKEW-1:0][DW-1:0] skew_q;
            always_ff @(posedge clk_adv) begin
                skew_q[0] <= i_a_data[r*DW +: DW];
                for (int k = 1; k < SKEW; k++)
                    skew_q[k] <= skew_q[k-1];
            end
            assign a_skewed[r*DW +: DW] = skew_q[SKEW-1];
        end
    end
endgenerate

array #(.N(N), .DW(DW), .ACC_W(ACC_W)) u_array (
    .i_w_stream (i_w_data),
    .i_a_left   (a_skewed),
    .i_psum_top ('0),
    .i_clk_w    (clk_w),
    .i_clk_adv  (clk_adv),
    .o_c_bottom (c_bottom)
);

genvar c;
generate
    for (c = 0; c < N; c++) begin : g_output_deskew
        localparam int DELAY = HOP * (N - 1 - c);
        if (DELAY == 0) begin : g_no_delay
            assign o_c_data[c*ACC_W +: ACC_W] = c_bottom[c*ACC_W +: ACC_W];
        end else begin : g_delay
            logic [DELAY-1:0][ACC_W-1:0] delay_q;
            always_ff @(posedge clk_adv) begin
                delay_q[0] <= c_bottom[c*ACC_W +: ACC_W];
                for (int k = 1; k < DELAY; k++)
                    delay_q[k] <= delay_q[k-1];
            end
            assign o_c_data[c*ACC_W +: ACC_W] = delay_q[DELAY-1];
        end
    end
endgenerate

always_ff @(posedge i_clk) begin
    if (!i_rstn || i_clear)
        valid_q <= '0;
    else if (i_a_advance)
        valid_q <= (valid_q << 1) | VALID_LAT'(i_a_valid);
end

assign o_c_valid = valid_q[VALID_LAT-1];

endmodule
`default_nettype wire
