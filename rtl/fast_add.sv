`default_nettype none
module fast_add #(
    parameter int W = 4
)(
    input logic [W-1:0] a,
    input logic [W-1:0] b,
    input logic  cin,
    output logic [W-1:0] sum,
    output logic cout
);
localparam int L = (W <= 1) ? 0 : $clog2(W);

logic [W-1:0] p;
logic [W-1:0] g;
wire [W-1:0] pp [0:L];
wire [W-1:0] gg [0:L];

assign p = a ^ b;
assign g = a & b;

assign gg[0][0] = g[0] | (p[0] & cin);
assign pp[0][0] = p[0];

genvar bit_idx;
generate
    for (bit_idx = 1; bit_idx < W; bit_idx++) begin : g_init
        assign gg[0][bit_idx] = g[bit_idx];
        assign pp[0][bit_idx] = p[bit_idx];
    end
endgenerate

genvar stage_idx;
genvar node_idx;
generate
    for (stage_idx = 0; stage_idx < L; stage_idx++) begin : g_stage
        for (node_idx = 0; node_idx < W; node_idx++) begin : g_node
            if (node_idx >= (1 << stage_idx)) begin : g_combine
                
                assign gg[stage_idx+1][node_idx] = gg[stage_idx][node_idx] |
                    (pp[stage_idx][node_idx] & gg[stage_idx][node_idx - (1 << stage_idx)]);
                
                assign pp[stage_idx+1][node_idx] = pp[stage_idx][node_idx] & pp[stage_idx][node_idx - (1 << stage_idx)];
            end else begin : g_pass
                assign gg[stage_idx+1][node_idx] = gg[stage_idx][node_idx];
                assign pp[stage_idx+1][node_idx] = pp[stage_idx][node_idx];
            end
        end
    end
endgenerate

assign sum[0] = p[0] ^ cin;

generate
    for (bit_idx = 1; bit_idx < W; bit_idx++) begin : g_sum
        assign sum[bit_idx] = p[bit_idx] ^ gg[L][bit_idx-1];
    end
endgenerate

assign cout = gg[L][W-1];

endmodule

module fast_add_cs #(
    parameter int W = 8,
    parameter int GROUP_W = 2
)(
    input logic [W-1:0] a,
    input logic [W-1:0] b,
    input logic cin,
    output logic [W-1:0] sum,
    output logic cout
);
localparam int GROUPS = (W + GROUP_W - 1) / GROUP_W;

wire carry [0:GROUPS];
assign carry[0] = cin;

genvar group_idx;
generate
    for (group_idx = 0; group_idx < GROUPS; group_idx++) begin : g_group
        localparam int LSB = group_idx * GROUP_W;
        localparam int GW = ((W - LSB) < GROUP_W) ? (W - LSB) : GROUP_W;

        wire [GW-1:0] sum_c0;
        wire [GW-1:0] sum_c1;
        wire cout_c0;
        wire cout_c1;

        fast_add #(.W(GW)) u_add_c0 (
            .a   (a[LSB +: GW]),
            .b   (b[LSB +: GW]),
            .cin (1'b0),
            .sum (sum_c0),
            .cout(cout_c0)
        );

        fast_add #(.W(GW)) u_add_c1 (
            .a   (a[LSB +: GW]),
            .b   (b[LSB +: GW]),
            .cin (1'b1),
            .sum (sum_c1),
            .cout(cout_c1)
        );

        assign sum[LSB +: GW] = carry[group_idx] ? sum_c1 : sum_c0;
        assign carry[group_idx+1] = carry[group_idx] ? cout_c1 : cout_c0;
    end
endgenerate

assign cout = carry[GROUPS];

endmodule
`default_nettype wire
