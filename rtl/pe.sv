`default_nettype none
module pe #(
    parameter int DW = sys_pkg::p_dw,
    parameter int ACC_W = sys_pkg::p_acc_w
) (
    input logic i_clk_w,
    input logic i_clk_adv,
    input logic signed [DW-1:0] i_w,
    input logic signed [DW-1:0] i_a,
    input logic signed [ACC_W-1:0] i_psum,
    output logic signed [DW-1:0] o_w,
    output logic signed [DW-1:0] o_a,
    output logic signed [ACC_W-1:0] o_psum
);

localparam int NL = $clog2(ACC_W);
localparam int KL = NL / 2;

function automatic logic [ACC_W-1:0] csa_s(input logic [ACC_W-1:0] x, y, z);
    csa_s = x ^ y ^ z;
endfunction

function automatic logic [ACC_W-1:0] csa_c(input logic [ACC_W-1:0] x, y, z);
    csa_c = ((x & y) | (x & z) | (y & z)) << 1;
endfunction

function automatic logic [2*ACC_W-1:0] ks_step(input logic [2*ACC_W-1:0] gp, input int d);
    logic [ACC_W-1:0] g, p, gn, pn;
    g = gp[2*ACC_W-1:ACC_W];
    p = gp[ACC_W-1:0];

    for (int i = 0; i < ACC_W; i++) begin
        if (i >= d) begin
            gn[i] = g[i] | (p[i] & g[i-d]);
            pn[i] = p[i] & p[i-d];
        end else begin
            gn[i] = g[i];
            pn[i] = p[i];
        end
    end

    ks_step = {gn, pn};
endfunction

logic signed [DW-1:0] a1, a2, a3, a4, a5, a6;
logic [ACC_W-1:0] p1;
logic [ACC_W-1:0] w_ext;
logic [ACC_W-1:0] r0, r1, r2, r3, r4, r5, r6, r7;

logic [ACC_W-1:0] t1_s0, t1_c0, t1_s1, t1_c1, t1_s2, t1_c2;
logic [ACC_W-1:0] t2_s0, t2_c0, t2_s1, t2_c1;
logic [ACC_W-1:0] t3_s, t3_c, t3_x;
logic [ACC_W-1:0] t4_s, t4_c;
logic [ACC_W-1:0] t5_p;
logic [2*ACC_W-1:0] t5_gp;
logic [2*ACC_W-1:0] ks_a, ks_b;
logic [ACC_W-1:0] sum_d;

always_ff @(posedge i_clk_w) begin
    o_w <= i_w;
end

assign w_ext = {{(ACC_W-DW){o_w[DW-1]}}, o_w};

always_comb begin
    r0 = a1[0] ? w_ext : '0;
    r1 = (a1[1] ? (w_ext << 1) : '0) | ACC_W'(a1[7]);
    r2 = a1[2] ? (w_ext << 2) : '0;
    r3 = a1[3] ? (w_ext << 3) : '0;
    r4 = a1[4] ? (w_ext << 4) : '0;
    r5 = a1[5] ? (w_ext << 5) : '0;
    r6 = a1[6] ? (w_ext << 6) : '0;
    r7 = a1[7] ? ~(w_ext << 7) : '0;
end

always_comb begin
    ks_a = {t4_s & t4_c, t4_s ^ t4_c};

    for (int k = 0; k < KL; k++) begin
        ks_a = ks_step(ks_a, 1 << k);
    end
end

always_comb begin
    ks_b = t5_gp;

    for (int k = KL; k < NL; k++) begin
        ks_b = ks_step(ks_b, 1 << k);
    end

    sum_d = t5_p ^ {ks_b[2*ACC_W-2:ACC_W], 1'b0};
end

always_ff @(posedge i_clk_adv) begin
    a1 <= i_a;
    p1 <= i_psum;

    a2 <= a1;
    a3 <= a2;
    a4 <= a3;
    a5 <= a4;
    a6 <= a5;
    o_a <= a6;

    t1_s0 <= csa_s(r0, r1, r2);
    t1_c0 <= csa_c(r0, r1, r2);
    t1_s1 <= csa_s(r3, r4, r5);
    t1_c1 <= csa_c(r3, r4, r5);
    t1_s2 <= csa_s(r6, r7, p1);
    t1_c2 <= csa_c(r6, r7, p1);

    t2_s0 <= csa_s(t1_s0, t1_c0, t1_s1);
    t2_c0 <= csa_c(t1_s0, t1_c0, t1_s1);
    t2_s1 <= csa_s(t1_c1, t1_s2, t1_c2);
    t2_c1 <= csa_c(t1_c1, t1_s2, t1_c2);

    t3_s <= csa_s(t2_s0, t2_c0, t2_s1);
    t3_c <= csa_c(t2_s0, t2_c0, t2_s1);
    t3_x <= t2_c1;

    t4_s <= csa_s(t3_s, t3_c, t3_x);
    t4_c <= csa_c(t3_s, t3_c, t3_x);

    t5_p <= t4_s ^ t4_c;
    t5_gp <= ks_a;

    o_psum <= sum_d;
end

endmodule
`default_nettype wire
