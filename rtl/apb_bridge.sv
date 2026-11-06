`default_nettype none
module apb_bridge #(
    parameter int APB_AW = 14,
    parameter int WBUF_AW = sys_pkg::p_wbuf_macro_aw,
    parameter int ABUF_AW = sys_pkg::p_abuf_aw,
    parameter int RBUF_AW = sys_pkg::p_rbuf_aw,
    parameter int DATA_W = sys_pkg::p_beat_w
) (
    input logic i_clk,
    input logic i_rstn,
    input logic i_psel,
    input logic i_penable,
    input logic i_pwrite,
    input logic [2:0] i_pprot,
    input logic [APB_AW-1:0] i_paddr,
    input logic [31:0] i_pwdata,
    input logic [3:0] i_pstrb,
    output logic o_pready,
    output logic [31:0] o_prdata,
    output logic o_pslverr,
    output logic o_csr_psel,
    output logic o_csr_penable,
    output logic o_csr_pwrite,
    output logic [2:0] o_csr_pprot,
    output logic [5:0] o_csr_paddr,
    output logic [31:0] o_csr_pwdata,
    output logic [3:0] o_csr_pstrb,
    input logic i_csr_pready,
    input logic [31:0] i_csr_prdata,
    input logic i_csr_pslverr,
    output logic o_wbuf_req,
    output logic o_wbuf_we,
    output logic [WBUF_AW-1:0] o_wbuf_addr,
    output logic [DATA_W-1:0] o_wbuf_wdata,
    output logic [DATA_W-1:0] o_wbuf_wmask,
    input logic i_wbuf_gnt,
    input logic i_wbuf_rvalid,
    input logic [DATA_W-1:0] i_wbuf_rdata,
    output logic o_abuf_req,
    output logic o_abuf_we,
    output logic [ABUF_AW-1:0] o_abuf_addr,
    output logic [DATA_W-1:0] o_abuf_wdata,
    output logic [DATA_W-1:0] o_abuf_wmask,
    input logic i_abuf_gnt,
    input logic i_abuf_rvalid,
    input logic [DATA_W-1:0] i_abuf_rdata,
    output logic o_rbuf_req,
    output logic o_rbuf_we,
    output logic [RBUF_AW-1:0] o_rbuf_addr,
    output logic [DATA_W-1:0] o_rbuf_wdata,
    output logic [DATA_W-1:0] o_rbuf_wmask,
    input logic i_rbuf_gnt,
    input logic i_rbuf_rvalid,
    input logic [DATA_W-1:0] i_rbuf_rdata
);
localparam logic [1:0] WIN_CSR = 2'd0;
localparam logic [1:0] WIN_WBUF = 2'd1;
localparam logic [1:0] WIN_ABUF = 2'd2;
localparam logic [1:0] WIN_RBUF = 2'd3;
 
logic [1:0] win;
logic [8:0] beat;
logic half_hi;
logic access, csr_ok, mem_ok, bad_access;
logic sw_req, sw_gnt, sw_rvalid, rd_wait_q, rd_done_q;
logic [DATA_W-1:0] sw_rdata, sw_wdata, sw_wmask;
logic [31:0] rd_data_q;
logic [31:0] strb_mask;
 
assign win = i_paddr[13:12];
assign beat = i_paddr[11:3];
assign half_hi = i_paddr[2];
assign access = i_psel & i_penable;
 
assign csr_ok = (win == WIN_CSR) & (i_paddr[11:6] == '0);
 
always_comb begin
    case (win)
        WIN_WBUF: mem_ok = (beat < 9'(sys_pkg::p_wbuf_macro_depth));
        WIN_ABUF: mem_ok = (beat < 9'(sys_pkg::p_abuf_depth));
        WIN_RBUF: mem_ok = (beat < 9'(sys_pkg::p_rbuf_depth)) & ~i_pwrite;
        default:  mem_ok = 1'b0;
    endcase
end
 
assign bad_access = access & ~csr_ok & ~mem_ok;
 
assign sw_req = access & mem_ok & ~rd_wait_q & ~rd_done_q;
 
assign strb_mask = {{8{i_pstrb[3]}}, {8{i_pstrb[2]}}, {8{i_pstrb[1]}}, {8{i_pstrb[0]}}};
assign sw_wdata = {i_pwdata, i_pwdata};
assign sw_wmask = half_hi ? {strb_mask, 32'b0} : {32'b0, strb_mask};
 
assign o_wbuf_req = sw_req & (win == WIN_WBUF);
assign o_wbuf_we = i_pwrite;
assign o_wbuf_addr = beat[WBUF_AW-1:0];
assign o_wbuf_wdata = sw_wdata;
assign o_wbuf_wmask = sw_wmask;
 
assign o_abuf_req = sw_req & (win == WIN_ABUF);
assign o_abuf_we = i_pwrite;
assign o_abuf_addr = beat[ABUF_AW-1:0];
assign o_abuf_wdata = sw_wdata;
assign o_abuf_wmask = sw_wmask;
 
assign o_rbuf_req = sw_req & (win == WIN_RBUF);
assign o_rbuf_we = i_pwrite;
assign o_rbuf_addr = beat[RBUF_AW-1:0];
assign o_rbuf_wdata = sw_wdata;
assign o_rbuf_wmask = sw_wmask;
 
always_comb begin
    sw_gnt = 1'b0;
    sw_rvalid = 1'b0;
    sw_rdata = '0;
    case (win)
        WIN_WBUF: begin
            sw_gnt = i_wbuf_gnt;
            sw_rvalid = i_wbuf_rvalid;
            sw_rdata = i_wbuf_rdata;
        end
        WIN_ABUF: begin
            sw_gnt = i_abuf_gnt;
            sw_rvalid = i_abuf_rvalid;
            sw_rdata = i_abuf_rdata;
        end
        WIN_RBUF: begin
            sw_gnt = i_rbuf_gnt;
            sw_rvalid = i_rbuf_rvalid;
            sw_rdata = i_rbuf_rdata;
        end
        default: ;
    endcase
end
 
always_ff @(posedge i_clk) begin
    if (!i_rstn) begin
        rd_wait_q <= 1'b0;
        rd_done_q <= 1'b0;
        rd_data_q <= '0;
    end else if (!access) begin
        rd_wait_q <= 1'b0;
        rd_done_q <= 1'b0;
    end else if (rd_wait_q & sw_rvalid) begin
        rd_wait_q <= 1'b0;
        rd_done_q <= 1'b1;
        rd_data_q <= half_hi ? sw_rdata[DATA_W-1 -: 32] : sw_rdata[31:0];
    end else if (sw_req & sw_gnt & ~i_pwrite) begin
        rd_wait_q <= 1'b1;
    end
end
 
// CSR pass-through
assign o_csr_psel = i_psel & csr_ok;
assign o_csr_penable = i_penable;
assign o_csr_pwrite = i_pwrite;
assign o_csr_pprot = i_pprot;
assign o_csr_paddr = i_paddr[5:0];
assign o_csr_pwdata = i_pwdata;
assign o_csr_pstrb = i_pstrb;
 
// response
always_comb begin
    o_pready = 1'b0;
    o_prdata = '0;
    o_pslverr = 1'b0;
    if (csr_ok) begin
        o_pready = i_csr_pready;
        o_prdata = i_csr_prdata;
        o_pslverr = i_csr_pslverr;
    end else if (bad_access) begin
        o_pready = 1'b1;
        o_pslverr = 1'b1;
    end else if (access & mem_ok) begin
        if (i_pwrite) begin
            o_pready = sw_req & sw_gnt;
        end else begin
            o_pready = rd_done_q;
            o_prdata = rd_data_q;
        end
    end
end
 
endmodule
`default_nettype wire
