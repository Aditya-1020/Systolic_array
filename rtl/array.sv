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

generate
    for (genvar row=0; row<N; row=row+1) begin : g_left
        assign a_wire[row][0] = i_a_left[row*DW +: DW];
    end

    for (genvar col=0; col<N; col=col+1) begin : g_top
        assign w_wire[0][col] = i_w_top[col*DW +: DW];
        assign psum_wire[0][col] = '0;
        assign o_c_bottom[col*ACC_W +: ACC_W] = psum_wire[N][col];
    end

    for (genvar row=0; row<N; row=row+1) begin : gen_pe_row
        for (genvar col=0; col<N; col=col+1) begin : gen_pe_col
            pe #(.DW(DW), .ACC_W(ACC_W)) pe_inst (
                .i_clk   (i_clk),
                .i_load_en(i_load_en),
                .i_w     (w_wire[row][col]),
                .i_a     (a_wire[row][col]),
                .i_psum  (psum_wire[row][col]),
                .o_w     (w_wire[row+1][col]),
                .o_a     (a_wire[row][col+1]),
                .o_psum  (psum_wire[row+1][col])
            );
        end
    end
endgenerate

endmodule
`default_nettype wire
