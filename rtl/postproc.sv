`default_nettype none
module postproc #(
    parameter int N = 8,
    parameter int IW = 32, // acc lane width
    parameter int DW = 8
)(
    input wire i_clk,
    input wire i_rstn,
    input wire [4:0] i_shift,
    input wire i_relu_en,
    input wire [N*IW-1:0] i_bias,
    input wire i_s_tvalid,
    input wire [N*IW-1:0] i_s_tdata,
    input wire i_s_tlast,
    output logic o_s_tready,
    input wire i_m_tready,
    output logic o_m_tvalid,
    output logic [N*DW-1:0] o_m_tdata,
    output logic o_m_tlast
);
localparam logic signed [IW+1:0] CMAX = (IW+2)'((1 <<< (DW-1)) - 1);
localparam logic signed [IW+1:0] CMIN = -(IW+2)'(1 <<< (DW-1));

logic [N*DW-1:0] y_flat;

genvar c;
generate
    for (c=0; c<N; c=c+1) begin : gen_lane
        logic signed [IW-1:0] acc, bias;
        logic signed [IW+1:0] s, rnd, v;
        logic signed [DW-1:0] y;
        assign acc = i_s_tdata[c*IW +: IW];
        assign bias = i_bias[c*IW +: IW];
        assign s = (IW+2)'(acc) + (IW+2)'(bias);
        assign rnd = (i_shift == 5'd0) ? '0 : ((IW+2)'(1) <<< (i_shift - 5'd1));
        assign v = (s + rnd) >>> i_shift;

        always_comb begin
            if (i_relu_en && (v<0)) y = '0;
            else if (v > CMAX) y = {1'b0, {(DW-1){1'b1}}};
            else if (v < CMIN) y = {1'b1, {(DW-1){1'b0}}};
            else y = v[DW-1:0];
        end

        assign y_flat[c*DW +: DW] = y;
    end
endgenerate

assign o_s_tready = !o_m_tvalid || i_m_tready;

always_ff @(posedge i_clk or negedge i_rstn) begin
    if (!i_rstn) begin
        o_m_tvalid <= '0;
    end else if (o_s_tready) begin
        o_m_tvalid <= i_s_tvalid;
    end
end


always_ff @(posedge i_clk) begin
    if (o_s_tready) begin
        o_m_tdata <= y_flat;
        o_m_tlast <= i_s_tlast;
    end
end
endmodule
`default_nettype wire
