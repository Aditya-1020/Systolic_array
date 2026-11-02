`default_nettype none
module accel_top #(
    parameter int N = 8,
    parameter int DW = 8,
    parameter int OUT_W = 32,
    parameter int Q_W = 8,
    parameter int MULT_W = 16,
    parameter int BIAS_W = 16,
    parameter int W_DEPTH = 256, // fakeram130_256x64
    parameter int A_DEPTH = 256, // fakeram130_256x64
    parameter int R_DEPTH = 512 // fakeram130_512x64
)(
    input wire i_clk,
    input wire i_rstn,
 
    input wire s_apb_psel,
    input wire s_apb_penable,
    input wire s_apb_pwrite,
    input logic [2:0] s_apb_pprot,
    input logic [14:0] s_apb_paddr,
    input logic [31:0] s_apb_pwdata,
    input logic [3:0] s_apb_pstrb,
    output logic s_apb_pready,
    output logic [31:0] s_apb_prdata,
    output logic s_apb_pslverr,
    output logic o_irq
);
 
localparam int MEM_DW = 64;
localparam int CSR_AW = 6;
localparam int W_AW = $clog2(W_DEPTH);
localparam int A_AW = $clog2(A_DEPTH);
localparam int R_AW = $clog2(R_DEPTH);
localparam int WIDX_W = 10;
 
localparam logic [1:0] SEL_CSR = 2'b00;
localparam logic [1:0] SEL_W = 2'b01;
localparam logic [1:0] SEL_A = 2'b10;
localparam logic [1:0] SEL_R = 2'b11;
 
logic [1:0] sel;
logic csr_hit, csr_sel, win_acc, in_range, host_ok, host_go, host_wr, host_rd, half;
logic [WIDX_W-1:0] widx;
logic rd_wait_q;
 
assign sel = s_apb_paddr[14:13];
assign csr_hit = (s_apb_paddr[12:CSR_AW] == '0); // CSR region is only 2**CSR_AW bytes, no aliasing
assign csr_sel = (sel == SEL_CSR) && csr_hit;
assign widx = s_apb_paddr[12:3];
assign half = s_apb_paddr[2];
 
always_comb begin
    in_range = 1'b0;
    unique case (sel)
        SEL_W: in_range = (widx < WIDX_W'(W_DEPTH));
        SEL_A: in_range = (widx < WIDX_W'(A_DEPTH));
        SEL_R: in_range = (widx < WIDX_W'(R_DEPTH));
        default: in_range = 1'b0;
    endcase
end
 
logic sys_busy;
logic csr_psel;
 
assign csr_psel = s_apb_psel && csr_sel;
assign win_acc = s_apb_psel && s_apb_penable && !csr_sel;
assign host_ok = !sys_busy && in_range;
assign host_go = win_acc && host_ok;
assign host_wr = host_go && s_apb_pwrite;
assign host_rd = host_go && !s_apb_pwrite && !rd_wait_q; // first access cycle of a read
 
always_ff @(posedge i_clk) begin
    if (!i_rstn) begin
        rd_wait_q <= 1'b0;
    end else begin
        rd_wait_q <= host_rd;
    end
end
 
logic [63:0] h_wd, h_mask;
 
assign h_wd = {s_apb_pwdata, s_apb_pwdata};
 
always_comb begin
    h_mask = '0;
    for (int k = 0; k < 8; k++) begin
        h_mask[8*k +: 8] = {8{((k / 4) == int'(half)) && s_apb_pstrb[k % 4]}};
    end
end
 
logic s_w_ce, s_a_ce, s_r_ce;
logic [W_AW-1:0] s_w_addr;
logic [A_AW-1:0] s_a_addr;
logic [R_AW-1:0] s_r_addr;
logic [63:0] s_r_wdata;
logic [63:0] rd_w, rd_a, rd_r;
 
logic [31:0] csr_prdata;
logic csr_pready, csr_pslverr;
 
systolic_top #(
    .N(N), .DW(DW), .OUT_W(OUT_W), .Q_W(Q_W), .MULT_W(MULT_W), .BIAS_W(BIAS_W),
    .MEM_DW(MEM_DW), .W_DEPTH(W_DEPTH), .A_DEPTH(A_DEPTH), .R_DEPTH(R_DEPTH), .CSR_AW(CSR_AW)
) u_sys (
    .i_clk        (i_clk),
    .i_rstn       (i_rstn),
    .s_apb_psel   (csr_psel),
    .s_apb_penable(s_apb_penable),
    .s_apb_pwrite (s_apb_pwrite),
    .s_apb_pprot  (s_apb_pprot),
    .s_apb_paddr  (s_apb_paddr[CSR_AW-1:0]),
    .s_apb_pwdata (s_apb_pwdata),
    .s_apb_pstrb  (s_apb_pstrb),
    .s_apb_pready (csr_pready),
    .s_apb_prdata (csr_prdata),
    .s_apb_pslverr(csr_pslverr),
    .o_irq        (o_irq),
    .o_busy       (sys_busy),
    .o_w_ce       (s_w_ce),
    .o_w_addr     (s_w_addr),
    .i_w_rdata    (rd_w),
    .o_a_ce       (s_a_ce),
    .o_a_addr     (s_a_addr),
    .i_a_rdata    (rd_a),
    .o_r_ce       (s_r_ce),
    .o_r_addr     (s_r_addr),
    .o_r_wdata    (s_r_wdata)
);
 
logic h_w, h_a, h_r;
logic ce_w, ce_a, ce_r, we_w, we_a, we_r;
logic [W_AW-1:0] addr_w;
logic [A_AW-1:0] addr_a;
logic [R_AW-1:0] addr_r;
logic [63:0] wd_r, mask_r;
 
assign h_w = (sel == SEL_W);
assign h_a = (sel == SEL_A);
assign h_r = (sel == SEL_R);
 
assign ce_w = s_w_ce || ((host_wr || host_rd) && h_w);
assign we_w = host_wr && h_w;
assign addr_w = sys_busy ? s_w_addr : W_AW'(widx);
 
assign ce_a = s_a_ce || ((host_wr || host_rd) && h_a);
assign we_a = host_wr && h_a;
assign addr_a = sys_busy ? s_a_addr : A_AW'(widx);
 
assign ce_r = s_r_ce || ((host_wr || host_rd) && h_r);
assign we_r = s_r_ce || (host_wr && h_r);
assign addr_r = sys_busy ? s_r_addr : R_AW'(widx);
assign wd_r = sys_busy ? s_r_wdata : h_wd;
assign mask_r = sys_busy ? 64'hFFFF_FFFF_FFFF_FFFF : h_mask;
 
fakeram130_256x64 u_wbuf (
    .rd_out(rd_w), .addr_in(addr_w), .we_in(we_w),
    .wd_in(h_wd), .w_mask_in(h_mask), .clk(i_clk), .ce_in(ce_w)
);
fakeram130_256x64 u_abuf (
    .rd_out(rd_a), .addr_in(addr_a), .we_in(we_a),
    .wd_in(h_wd), .w_mask_in(h_mask), .clk(i_clk), .ce_in(ce_a)
);
fakeram130_512x64 u_rbuf (
    .rd_out(rd_r), .addr_in(addr_r), .we_in(we_r),
    .wd_in(wd_r), .w_mask_in(mask_r), .clk(i_clk), .ce_in(ce_r)
);
 
// APB response mux
logic [63:0] h_rdata;
logic [31:0] win_prdata;
logic win_pready, win_pslverr;
 
always_comb begin
    h_rdata = rd_r;
    unique case (sel)
        SEL_W: h_rdata = rd_w;
        SEL_A: h_rdata = rd_a;
        default: h_rdata = rd_r;
    endcase
end
 
assign win_prdata = (rd_wait_q && host_ok) ? (half ? h_rdata[63:32] : h_rdata[31:0]) : 32'd0;
 
always_comb begin
    win_pready = 1'b0;
    win_pslverr = 1'b0;
    if (win_acc) begin
        if (!host_ok) begin
            win_pready = 1'b1;
            win_pslverr = 1'b1;
        end else if (s_apb_pwrite) begin
            win_pready = 1'b1;
        end else begin
            win_pready = rd_wait_q;
        end
    end
end
 
assign s_apb_pready = csr_sel ? csr_pready : win_pready;
assign s_apb_prdata = csr_sel ? csr_prdata : win_prdata;
assign s_apb_pslverr = csr_sel ? csr_pslverr : win_pslverr;
 
endmodule
`default_nettype wire
