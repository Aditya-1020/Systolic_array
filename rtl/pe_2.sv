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

localparam int NPP = DW / 2; // Booth rows
localparam int NL = $clog2(ACC_W); // prefix levels
localparam int BIAS_MAG = (1 << DW) * (((1 << (2*NPP)) - 1) / 3);
localparam logic [ACC_W-1:0] P_BIAS = ACC_W'(0) - ACC_W'(BIAS_MAG);

function automatic logic [2:0] booth_dec(input logic [2:0] grp);
    logic sel1, sel2, neg;
    sel1 = grp[1] ^ grp[0];
    sel2 = (grp[2] & ~grp[1] & ~grp[0]) | (~grp[2] & grp[1] & grp[0]);
    neg = grp[2] & ~(grp[1] & grp[0]);

    booth_dec = {neg, sel2, sel1};
endfunction

function automatic logic [DW+1:0] booth_pp(
    input logic [2:0] ctl,    // {neg, sel2, sel1}
    input logic [DW-1:0] w
);
    logic [DW:0] w_x1, w_x2, mag, row;
    w_x1 = {w[DW-1], w};
    w_x2 = {w, 1'b0};
    mag = ({(DW+1){ctl[0]}} & w_x1) | ({(DW+1){ctl[1]}} & w_x2);
    row = mag ^ {(DW+1){ctl[2]}};
    booth_pp = {ctl[2], ~row[DW], row[DW-1:0]};
endfunction

function automatic logic [ACC_W-1:0] csa_s(
    input logic [ACC_W-1:0] x,
    input logic [ACC_W-1:0] y,
    input logic [ACC_W-1:0] z
);
    csa_s = x ^ y ^ z;
endfunction

function automatic logic [ACC_W-1:0] csa_c(
    input logic [ACC_W-1:0] x,
    input logic [ACC_W-1:0] y,
    input logic [ACC_W-1:0] z
);
    logic [ACC_W-1:0] maj;
    maj = (x & y) | (x & z) | (y & z);
    csa_c = {maj[ACC_W-2:0], 1'b0};
endfunction

function automatic logic [ACC_W-1:0] ks_add(input logic [ACC_W-1:0] x, input logic [ACC_W-1:0] y);
    logic [ACC_W-1:0] p0, g, p, gn, pn;
    p0 = x ^ y;
    g = x & y;
    p = p0;
    for (int k = 0; k < NL; k++) begin
        for (int i = 0; i < ACC_W; i++) begin
            if (i >= (1 << k)) begin
                gn[i] = g[i] | (p[i] & g[i - (1 << k)]);
                pn[i] = p[i] & p[i - (1 << k)];
            end else begin
                gn[i] = g[i];
                pn[i] = p[i];
            end
        end
        g = gn;
        p = pn;
    end
    ks_add = p0 ^ {g[ACC_W-2:0], 1'b0};
endfunction

logic [DW:0] ab_in; // {i_a, 0} booth multiplier
logic [NPP-1:0][2:0] ctl_d; // decoded {neg, sel2, sel1}
logic [DW+1:0] pp [NPP]; // {neg, u} per row
logic [ACC_W-1:0] r0, r1, r2, r3, rk; // CSA tree inputs
logic [ACC_W-1:0] l1_s0, l1_c0, l1_s1, l1_c1;
logic [ACC_W-1:0] next_s, next_c, next_x;
logic [ACC_W-1:0] fin_s, fin_c;
logic [ACC_W-1:0] next_sum;

logic [DW-1:0] a_q, a_d_q;
logic [ACC_W-1:0] p_q;
logic [NPP-1:0][2:0] ctl_q;
logic [ACC_W-1:0] s_q, c_q, x_q;

always_ff @(posedge i_clk_w) begin
    o_w <= i_w;
end

// S1: booth partial prod + csa tree
assign ab_in = {i_a, 1'b0};
for (genvar k = 0; k < NPP; k++) begin : g_pp
    assign ctl_d[k] = booth_dec(ab_in[2*k +: 3]);
    assign pp[k] = booth_pp(ctl_q[k], o_w);
end

assign r0 = ACC_W'(pp[0][DW:0]);
assign r1 = (ACC_W'(pp[1][DW:0]) << 2) | ACC_W'(pp[0][DW+1]);
assign r2 = (ACC_W'(pp[2][DW:0]) << 4) | (ACC_W'(pp[1][DW+1]) << 2);
assign r3 = (ACC_W'(pp[3][DW:0]) << 6) | (ACC_W'(pp[2][DW+1]) << 4);
assign rk = P_BIAS | (ACC_W'(pp[3][DW+1]) << 6);

assign l1_s0 = csa_s(r0, r1, r2);
assign l1_c0 = csa_c(r0, r1, r2);
assign l1_s1 = csa_s(r3, p_q, rk);
assign l1_c1 = csa_c(r3, p_q, rk);

// 2 csa levels
assign next_s = csa_s(l1_s0, l1_c0, l1_s1);
assign next_c = csa_c(l1_s0, l1_c0, l1_s1);
assign next_x = l1_c1;

// S2: cpa
assign fin_s = csa_s(s_q, c_q, x_q);
assign fin_c = csa_c(s_q, c_q, x_q);
assign next_sum = ks_add(fin_s, fin_c);

// pipline registers
always_ff @(posedge i_clk_adv) begin
    a_q <= i_a;
    a_d_q <= a_q;
    o_a <= a_d_q;
    p_q <= i_psum;
    ctl_q <= ctl_d;
    s_q <= next_s;
    c_q <= next_c;
    x_q <= next_x;
    o_psum <= next_sum;
end

endmodule
`default_nettype wire
