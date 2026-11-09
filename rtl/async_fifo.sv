module async_fifo #(
    parameter int WIDTH = 8,
    parameter int DEPTH = 4,
    parameter bit ONEHOT_RD = 1'b0
)(
    input logic wr_clk,
    input logic wr_rstn,
    input logic wr_en,
    input logic [WIDTH-1:0] wr_data,
    output logic wr_full,
 
    input logic rd_clk,
    input logic rd_rstn,
    input logic rd_en,
    output logic [WIDTH-1:0] rd_data,
    output logic rd_empty
);
localparam int AW = $clog2(DEPTH);
localparam int PW = AW + 1;
localparam logic [PW-1:0] FULL_XOR_MASK = PW'(3) << (AW - 1);

`ifndef SYNTHESIS
initial begin
    if (DEPTH < 2 || (DEPTH & (DEPTH - 1)) != 0)
        $error("async_fifo DEPTH must be a power of two and at least 2 (got %0d)", DEPTH);
    if (WIDTH < 1)
        $error("async_fifo WIDTH must be greater than zero (got %0d)", WIDTH);
end
`endif
 
logic [PW-1:0] wr_bin_q, rd_bin_q;
logic [PW-1:0] wr_gray_q, rd_gray_q;
(* ASYNC_REG = "TRUE" *) logic [PW-1:0] wr_gray_rd_q1, wr_gray_rd_q2;
(* ASYNC_REG = "TRUE" *) logic [PW-1:0] rd_gray_wr_q1, rd_gray_wr_q2;
logic [PW-1:0] wr_bin_inc, rd_bin_inc;
logic [PW-1:0] wr_gray_inc, rd_gray_inc;
logic wr_full_if_hold, wr_full_if_push;
logic rd_empty_if_hold, rd_empty_if_pop;
logic wr_fire, rd_fire;
logic [DEPTH-1:0][WIDTH-1:0] entry_bus;
logic wr_full_q, rd_empty_q;
 
function automatic logic [PW-1:0] b2g(input logic [PW-1:0] b);
    return b ^ (b >> 1);
endfunction
 
assign wr_full =wr_full_q;
assign rd_empty = rd_empty_q;
 
assign wr_fire = wr_en & ~wr_full_q;
assign rd_fire = rd_en & ~rd_empty_q;
 
assign wr_bin_inc = wr_bin_q + PW'(1);
assign rd_bin_inc = rd_bin_q + PW'(1);
assign wr_gray_inc = b2g(wr_bin_inc);
assign rd_gray_inc = b2g(rd_bin_inc);
 
assign wr_full_if_hold  = (wr_gray_q   == (rd_gray_wr_q2 ^ FULL_XOR_MASK));
assign wr_full_if_push  = (wr_gray_inc == (rd_gray_wr_q2 ^ FULL_XOR_MASK));
assign rd_empty_if_hold = (rd_gray_q   == wr_gray_rd_q2);
assign rd_empty_if_pop  = (rd_gray_inc == wr_gray_rd_q2);
 
always_ff @(posedge wr_clk) begin
    if (!wr_rstn) begin
        wr_bin_q <= '0;
        wr_gray_q <= '0;
        wr_full_q <= 1'b0;
    end else begin
        if (wr_fire) begin
            wr_bin_q <= wr_bin_inc;
            wr_gray_q <= wr_gray_inc;
        end
        wr_full_q <= wr_fire ? wr_full_if_push : wr_full_if_hold;
    end
end
 
// per entry icg for fanouts
genvar gi;
generate
    for (gi = 0; gi < DEPTH; gi++) begin : g_mem
        logic wr_sel;
        logic mem_clk;
        logic [WIDTH-1:0] q;
 
        assign wr_sel = wr_fire & (wr_bin_q[AW-1:0] == AW'(gi));
        OPENROAD_CLKGATE u_cg_mem (.CK(wr_clk), .E(wr_sel), .GCK(mem_clk));
 
        always_ff @(posedge mem_clk) begin
            q <= wr_data;
        end
 
        assign entry_bus[gi] = q;
    end
endgenerate
 
always_ff @(posedge wr_clk) begin
    if (!wr_rstn) begin
        rd_gray_wr_q1 <= '0;
        rd_gray_wr_q2 <= '0;
    end else begin
        rd_gray_wr_q1 <= rd_gray_q;
        rd_gray_wr_q2 <= rd_gray_wr_q1;
    end
end
 
always_ff @(posedge rd_clk) begin
    if (!rd_rstn) begin
        rd_bin_q <= '0;
        rd_gray_q <= '0;
        rd_empty_q <= 1'b1;
    end else begin
        if (rd_fire) begin
            rd_bin_q <= rd_bin_inc;
            rd_gray_q <= rd_gray_inc;
        end
        rd_empty_q <= rd_fire ? rd_empty_if_pop : rd_empty_if_hold;
    end
end
 
always_ff @(posedge rd_clk) begin
    if (!rd_rstn) begin
        wr_gray_rd_q1 <= '0;
        wr_gray_rd_q2 <= '0;
    end else begin
        wr_gray_rd_q1 <= wr_gray_q;
        wr_gray_rd_q2 <= wr_gray_rd_q1;
    end
end
 
generate
    if (ONEHOT_RD) begin : g_onehot_rd
        logic [DEPTH-1:0] rd_sel_q;
 
        always_ff @(posedge rd_clk) begin
            if (!rd_rstn) begin
                rd_sel_q <= {{(DEPTH-1){1'b0}}, 1'b1};
            end else if (rd_fire) begin
                rd_sel_q <= (rd_sel_q << 1) | {{(DEPTH-1){1'b0}}, rd_sel_q[DEPTH-1]};
            end
        end
 
        always_comb begin
            rd_data = '0;
            for (int i = 0; i < DEPTH; i++) begin
                rd_data |= entry_bus[i] & {WIDTH{rd_sel_q[i]}};
            end
        end
    end else begin : g_binary_rd
        assign rd_data = entry_bus[rd_bin_q[AW-1:0]];
    end
endgenerate
 
endmodule
`default_nettype wire
