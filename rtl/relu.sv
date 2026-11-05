`default_nettype none
module relu #(
    parameter int N = sys_pkg::p_n,
    parameter int DW = sys_pkg::p_dw,
    parameter int ACC_W = sys_pkg::p_acc_w
) (
    input logic [N*ACC_W-1:0] i_data,
    input logic i_relu_en,
    output logic [N*DW-1:0] o_data
);
localparam logic signed [ACC_W-1:0] MAX_DW = (1 <<< (DW-1)) - 1;
localparam logic signed [ACC_W-1:0] MIN_DW = -(1 <<< (DW-1));

genvar lane;
generate
    for (lane = 0; lane < N; lane++) begin : g_lane
        logic signed [ACC_W-1:0] value_s;
        logic signed [DW-1:0] result_s;

        always_comb begin
            value_s = $signed(i_data[lane*ACC_W +: ACC_W]);
            if (i_relu_en && (value_s < 0))
                result_s = '0;
            else if (value_s > MAX_DW)
                result_s = {1'b0, {(DW-1){1'b1}}};
            else if (value_s < MIN_DW)
                result_s = {1'b1, {(DW-1){1'b0}}};
            else
                result_s = value_s[DW-1:0];
            o_data[lane*DW +: DW] = result_s;
        end
    end
endgenerate

endmodule
`default_nettype wire
