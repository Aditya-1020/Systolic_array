`default_nettype none

module array #(
    parameter int N = 8,
    parameter int DW = 8,
    parameter int ACC_W = 32
)(
    input wire i_clk,
    input wire i_load_en,
    input wire signed [N*DW-1:0] i_w_top,
    input wire signed [N*DW-1:0] i_a_left,
    output logic signed [N*ACC_W-1:0] o_c_bottom
);
logic signed [DW-1:0] a_wire [0:N-1][0:N];
logic signed [DW-1:0] w_wire [0:N][0:N-1];
logic signed [ACC_W-1:0] psum_wire [0:N][0:N-1];

genvar i, j;
generate
    for (i=0; i<N; i=i+1) begin : g_left
        assign a_wire[i][0] = i_a_left[i*DW +: DW];
    end

    for (j=0; j<N; j=j+1) begin : g_top
        assign w_wire[0][j] = i_w_top[j*DW +: DW];
        assign psum_wire[0][j] = '0;
        assign o_c_bottom[j*ACC_W +: ACC_W] = psum_wire[N][j];
    end

    for (i=0; i<N; i=i+1) begin : gen_pe_row
        for (j=0; j<N; j=j+1) begin : gen_pe_col
            pe #(
                .DW(DW),
                .ACC_W(ACC_W)
            ) pe_inst (
                .i_clk   (i_clk),
                .i_load_en(i_load_en),
                .i_w     (w_wire[i][j]),
                .i_a     (a_wire[i][j]),
                .i_psum  (psum_wire[i][j]),
                .o_w     (w_wire[i+1][j]),
                .o_a     (a_wire[i][j+1]),
                .o_psum  (psum_wire[i+1][j])
            );
        end
    end
endgenerate

endmodule
`default_nettype wire
