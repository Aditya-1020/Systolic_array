`default_nettype none
module postproc #(
    parameter int N = sys_pkg::p_n,
    parameter int DW = sys_pkg::p_dw,
    parameter int ACC_W = sys_pkg::p_acc_w,
    parameter int SH_W = sys_pkg::p_shift_w
) (
    input logic i_clk,
    input logic i_rstn,
    input logic i_post_proc_en,
    input logic [ACC_W-1:0] i_round_const,
    input logic i_relu_en,
    input logic [SH_W-1:0] i_shift,
    input logic i_arr_valid,
    input logic [N*ACC_W-1:0] i_sys_data,
    output logic o_post_proc_ready,
    output logic o_round_valid,
    output logic [N*ACC_W-1:0] o_round_data,
    output logic o_relu_valid,
    output logic [N*DW-1:0] o_relu_data,
    output logic [N*DW-1:0] o_post_proc_data
);
localparam int PIPE = 6;
localparam int EXT_W = ACC_W + 1;
localparam int NCH = 4; // adder chunks
localparam int CW = (EXT_W + NCH - 1)/ NCH;
localparam int SEL_REP = 4;

logic pp_fire;
logic [PIPE-1:0] valid_q;
logic clk_s0, clk_s1, clk_s2, clk_s3, clk_s4, clk_s5;

logic [SH_W-1:0] shift_c_q, shift_a_q, shift_s_q;
logic relu_en_c_q, relu_en_a_q, relu_en_s_q, relu_en_l_q;
logic [N*ACC_W-1:0] data_c_q, round_q, round_comb;
logic [N*EXT_W-1:0] mid_q, mid_comb;
logic [N*DW-1:0] relu_q, relu_comb;

//logic nz_shift;
assign pp_fire = i_post_proc_en & i_arr_valid;
// assign nz_shift = |i_shift;

genvar lane, k, g, b;
generate
    for (lane = 0; lane < N; lane++) begin : gen_lane
        logic [EXT_W-1:0] bias_d, bias_q;
        assign bias_d = {1'b0, i_round_const};
        pp_reg_reg #(.W(EXT_W)) u_bias (.i_clk(clk_s0), .i_d(bias_d), .o_q(bias_q));
        logic [EXT_W-1:0] x_ext;
        assign x_ext = {data_c_q[lane*ACC_W + ACC_W-1], data_c_q[lane*ACC_W +: ACC_W]};

        logic [EXT_W-1:0] ch_sum_q;
        logic [NCH-1:0] ch_co_q, ch_pa_q;
        
        for (k = 0; k < NCH; k++) begin : gen_add
            localparam int LSB = k * CW;
            localparam int WK = (k == NCH-1) ? (EXT_W - LSB) : CW;
            logic [WK:0] s;
            logic pa;
            always_comb begin
                s = {1'b0, x_ext[LSB +: WK]} + {1'b0, bias_q[LSB +: WK]};
                pa = &(x_ext[LSB +: WK] ^ bias_q[LSB +: WK]); // sum 1s if b=~x
            end
            
            always_ff @(posedge clk_s1) begin
                ch_sum_q[LSB+:WK] <= s[WK-1:0];
                ch_co_q[k] <= s[WK];
                ch_pa_q[k] <= pa;
            end
        end

        logic [NCH-1:0] cin;
        logic c_chain;
        logic [EXT_W-1:0] res, sum_l_q;
        always_comb begin
            c_chain = 1'b0;
            cin[0] = 1'b0;
            for (int i = 1; i < NCH; i++) begin
                c_chain = ch_co_q[i-1] | (ch_pa_q[i-1] & c_chain);
                cin[i] = c_chain;
            end
        end

        for (k = 0; k < NCH; k++) begin : gen_inc
            localparam int LSB = k * CW;
            localparam int WK = (k == NCH-1) ? (EXT_W - LSB) : CW;
            logic [WK-1:0] pref;
            logic p_chain;
            always_comb begin
                p_chain = 1'b1;
                for (int j = 0; j < WK; j++) begin
                    pref[j] = p_chain;
                    p_chain = p_chain & ch_sum_q[LSB + j];
                end
            end

            assign res[LSB +: WK] = ch_sum_q[LSB +: WK] ^ (pref & {WK{cin[k]}});
        end

        always_ff @(posedge clk_s2) begin
            sum_l_q <= res;
        end
        
        for (g = 0; g < SEL_REP; g++) begin : g_sa
            localparam int B0 = (g * EXT_W) / SEL_REP;
            localparam int B1 = ((g + 1) * EXT_W) / SEL_REP;
            logic [1:0] sel;

            pp_reg_reg #(.W(2)) u_sel (.i_clk(clk_s2), .i_d(shift_a_q[1:0]), .o_q(sel));
            
            for (b = B0; b < B1; b++) begin : g_bit
                localparam int I1 = (b + 1 > EXT_W - 1) ? EXT_W - 1 : b + 1;
                localparam int I2 = (b + 2 > EXT_W - 1) ? EXT_W - 1 : b + 2;
                localparam int I3 = (b + 3 > EXT_W - 1) ? EXT_W - 1 : b + 3;
                
                always_comb begin
                    case (sel)
                        2'd0: mid_comb[lane*EXT_W + b] = sum_l_q[b];
                        2'd1: mid_comb[lane*EXT_W + b] = sum_l_q[I1];
                        2'd2: mid_comb[lane*EXT_W + b] = sum_l_q[I2];
                        default: mid_comb[lane*EXT_W + b] = sum_l_q[I3];
                    endcase
                end
            end
        end

        for (g = 0; g < SEL_REP; g++) begin : g_sb
            localparam int B0 = (g * ACC_W) / SEL_REP;
            localparam int B1 = ((g + 1) * ACC_W) / SEL_REP;
            logic [SH_W-3:0] sel;
           
            pp_reg_reg #(.W(SH_W-2)) u_sel (.i_clk(clk_s3), .i_d(shift_s_q[SH_W-1:2]), .o_q(sel));
            
            for (b = B0; b < B1; b++) begin : g_bit
                localparam int C4 = (b + 4  > EXT_W - 1) ? EXT_W - 1 : b + 4;
                localparam int C8 = (b + 8  > EXT_W - 1) ? EXT_W - 1 : b + 8;
                localparam int C12 = (b + 12 > EXT_W - 1) ? EXT_W - 1 : b + 12;
                localparam int C16 = (b + 16 > EXT_W - 1) ? EXT_W - 1 : b + 16;
                always_comb begin
                    case (sel)
                        'd0: round_comb[lane*ACC_W + b] = mid_q[lane*EXT_W + b];
                        'd1: round_comb[lane*ACC_W + b] = mid_q[lane*EXT_W + C4];
                        'd2: round_comb[lane*ACC_W + b] = mid_q[lane*EXT_W + C8];
                        'd3: round_comb[lane*ACC_W + b] = mid_q[lane*EXT_W + C12];
                        default: round_comb[lane*ACC_W + b] = mid_q[lane*EXT_W + C16];
                    endcase
                end
            end
        end

        logic relu_en;
        pp_reg_reg #(.W(1)) u_ren (.i_clk(clk_s4), .i_d(relu_en_l_q), .o_q(relu_en));
        relu #(.N(1), .DW(DW), .ACC_W(ACC_W)) u_relu (
            .i_data   (round_q[lane*ACC_W +: ACC_W]),
            .i_relu_en(relu_en),
            .o_data   (relu_comb[lane*DW +: DW])
        );
    end
endgenerate

always_ff @(posedge i_clk) begin
    if (!i_rstn) begin
        valid_q <= '0;
    end else begin
        valid_q <= {valid_q[PIPE-2:0], pp_fire};
    end
end

OPENROAD_CLKGATE u_cg_s0 (.CK(i_clk), .E(pp_fire),    .GCK(clk_s0));
OPENROAD_CLKGATE u_cg_s1 (.CK(i_clk), .E(valid_q[0]), .GCK(clk_s1));
OPENROAD_CLKGATE u_cg_s2 (.CK(i_clk), .E(valid_q[1]), .GCK(clk_s2));
OPENROAD_CLKGATE u_cg_s3 (.CK(i_clk), .E(valid_q[2]), .GCK(clk_s3));
OPENROAD_CLKGATE u_cg_s4 (.CK(i_clk), .E(valid_q[3]), .GCK(clk_s4));
OPENROAD_CLKGATE u_cg_s5 (.CK(i_clk), .E(valid_q[4]), .GCK(clk_s5));


always_ff @(posedge clk_s0) begin
    data_c_q <= i_sys_data;
    shift_c_q <= i_shift;
    relu_en_c_q <= i_relu_en;
end
always_ff @(posedge clk_s1) begin
    shift_a_q <= shift_c_q;
    relu_en_a_q <= relu_en_c_q;
end
always_ff @(posedge clk_s2) begin
    shift_s_q <= shift_a_q;
    relu_en_s_q <= relu_en_a_q;
end
always_ff @(posedge clk_s3) begin
    mid_q <= mid_comb;
    relu_en_l_q <= relu_en_s_q;
end
always_ff @(posedge clk_s4) begin
    round_q <= round_comb;
end
always_ff @(posedge clk_s5) begin
    relu_q  <= relu_comb;
end

assign o_post_proc_ready = i_post_proc_en;
assign o_round_valid = valid_q[4];
assign o_round_data = round_q;
assign o_relu_valid = valid_q[5];
assign o_relu_data = relu_q;
assign o_post_proc_data = relu_q;

endmodule
`default_nettype wire
