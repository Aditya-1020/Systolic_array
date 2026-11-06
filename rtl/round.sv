`default_nettype none
module round #(
    parameter int N = sys_pkg::p_n,
    parameter int ACC_W = sys_pkg::p_acc_w,
    parameter int SH_W = sys_pkg::p_shift_w
) (
    input logic [N*ACC_W-1:0] i_data,
    input logic [SH_W-1:0] i_shift,
    input logic [ACC_W-1:0] i_round_const,
    output logic [N*ACC_W-1:0] o_data
);
genvar lane;
generate
    for (lane = 0; lane < N; lane++) begin : g_lane
        logic signed [ACC_W:0] x_ext, bias_ext, sum_ext;
        logic [ACC_W:0] bias_bits;

        always_comb begin
            x_ext = $signed({i_data[lane*ACC_W + ACC_W-1], i_data[lane*ACC_W +: ACC_W]});
            bias_bits = (i_shift == '0) ? '0 : {1'b0, i_round_const};
            bias_ext = $signed(bias_bits);
            sum_ext = x_ext + bias_ext;
            // Truncate after arithmetic shift; MSB of sum_ext is only for headroom.
            o_data[lane*ACC_W +: ACC_W] = ACC_W'(sum_ext >>> i_shift);
        end
    end
endgenerate
endmodule
`default_nettype wire
