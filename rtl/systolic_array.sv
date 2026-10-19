`default_nettype none
module systolic_array #(
    parameter int N = 8,
    parameter int DW = 8,
    parameter int ACC_W = 2*DW + $clog2(N),
    parameter int ADDR_W = 32,
    parameter int LEN_W = 32
)(
    input wire i_clk,
    input wire i_rstn,
    input wire start,
    
    input wire cfg_load_w,
    input wire [ADDR_W-1:0] cfg_w_base,
    input wire [ADDR_W-1:0] cfg_a_base,
    input wire [ADDR_W-1:0] cfg_o_base,
    input wire [LEN_W-1:0] cfg_len,

    output logic busy,
    output logic done,
    output logic weights_loaded,

    // shared rdport weights then act
    input wire rd_gnt,
    input wire rd_rvalid,
    input wire signed [N*DW-1:0] rd_rdata,
    output logic rd_req,
    output logic [ADDR_W-1:0] rd_addr,
    
    output logic wr_en,
    output logic [ADDR_W-1:0] wr_addr,
    output logic signed [N*ACC_W-1:0] wr_data
);
localparam int WEIGHT_CNT_W = (N>1) ? $clog2(N+1) : 1;
localparam int LENGTH_CNT_W = LEN_W + 1;
localparam int VALID_LATENCY = 2*N - 1;
localparam int SKEW_STAGES = (N>1) ? N-1 : 1;

typedef enum logic [1:0] {
    IDLE,
    LOAD_WEIGHTS,
    LOAD_ACTIVATIONS,
    FLUSH
} state_t;
state_t state;

logic [ADDR_W-1:0] w_base_q, a_base_q, o_base_q;
logic [LEN_W-1:0] len_q;

logic [WEIGHT_CNT_W-1:0] w_req_cnt, w_rsp_cnt;
logic [LENGTH_CNT_W-1:0] a_req_cnt, a_rsp_cnt;
logic [LENGTH_CNT_W-1:0] out_cnt;

logic signed [N*DW-1:0] a_q;
logic a_valid_q;
logic [VALID_LATENCY-1:0] valid_pipe;

logic signed [N*DW-1:0] a_skew_data [0:SKEW_STAGES-1];
logic signed [N*DW-1:0] a_left;
logic signed [N*ACC_W-1:0] array_bottom;
logic signed [N*ACC_W-1:0] aligned_data;

wire rstn_sync, weight_load_en;
reset_sync u_rst_sync ( .clk(i_clk), .arstn(i_rstn), .rstn_sync(rstn_sync) );

assign busy = (state !== IDLE);
assign weight_load_en = (state == LOAD_WEIGHTS) && rd_rvalid;
assign wr_en = valid_pipe[VALID_LATENCY-1];
assign wr_data = aligned_data;
assign wr_addr = o_base_q + ADDR_W'(out_cnt);

always_comb begin
    rd_req = 1'b0;
    rd_addr = '0;

    unique case (state)
        LOAD_WEIGHTS: begin
            if (w_req_cnt < N) begin
                rd_req = 1'b1;
                rd_addr = w_base_q + ADDR_W'(N - 1 - w_req_cnt);
            end
        end
        
        LOAD_ACTIVATIONS: begin
            if (a_req_cnt < {1'b0, len_q}) begin
                rd_req = 1'b1;
                rd_addr = a_base_q + ADDR_W'(a_req_cnt);
            end
        end

        default: begin
            rd_req = 1'b0;
            rd_addr = '0;
        end
    endcase
end

always_ff @(posedge i_clk or negedge rstn_sync) begin
    if (!rstn_sync) begin
        state <= IDLE;
        done <= 1'b0;
        weights_loaded <= 1'b0;
        w_base_q <= '0;
        a_base_q <= '0;
        o_base_q <= '0;
        len_q <= '0;
        w_req_cnt <= '0;
        w_rsp_cnt <= '0;
        a_req_cnt <= '0;
        out_cnt <= '0;
    end else begin
        done <= 1'b0;
        if (wr_en) begin
            out_cnt <= out_cnt + 1'b1;
        end

        unique case (state)
            IDLE: begin
                if (start && (cfg_len !== '0) && (cfg_load_w || weights_loaded)) begin
                    w_base_q <= cfg_w_base;
                    a_base_q <= cfg_a_base;
                    o_base_q <= cfg_o_base;
                    len_q <= cfg_len;
                    
                    w_req_cnt <= '0;
                    w_rsp_cnt <= '0;
                    a_req_cnt <= '0;
                    a_rsp_cnt <= '0;
                    out_cnt <= '0;

                    if (cfg_load_w) begin
                        weights_loaded <= 1'b0;
                        state <= LOAD_WEIGHTS;
                    end else begin
                        state <= LOAD_ACTIVATIONS;
                    end
                end
            end

            LOAD_WEIGHTS: begin
                if (rd_req && rd_gnt) begin
                    w_req_cnt <= w_req_cnt + 1'b1;
                end

                if (rd_rvalid) begin
                    if (w_rsp_cnt == N-1) begin
                        weights_loaded <= 1'b1;
                        a_req_cnt <= '0;
                        a_rsp_cnt <= '0;
                        state <= LOAD_ACTIVATIONS;
                    end else begin
                        w_rsp_cnt <= w_rsp_cnt + 1'b1;
                    end
                end
            end

            LOAD_ACTIVATIONS: begin
                if (rd_req && rd_gnt) begin
                    a_req_cnt <= a_req_cnt + 1'b1;
                end
                
                if (rd_rvalid) begin
                    a_rsp_cnt <= a_rsp_cnt + 1'b1;
                    if (a_rsp_cnt == ({1'b0, len_q} - 1'b1)) begin
                        state <= FLUSH;
                    end
                end
            end

            FLUSH: begin
                if (!a_valid_q && !(|valid_pipe) && (out_cnt == {1'b0, len_q})) begin
                    done <= 1'b1;
                    state <= IDLE;
                end
            end

            default: begin
                state <= IDLE;
                weights_loaded <= 1'b0;
            end
        endcase
    end
end

always_ff @(posedge i_clk or negedge rstn_sync) begin
    if (!rstn_sync) begin
        a_q <= '0;
        a_valid_q <= 1'b0;
        valid_pipe <= '0;
    end else begin
        a_q <= '0;
        a_valid_q <= 1'b0;

        if ((state == LOAD_ACTIVATIONS) && rd_rvalid) begin
            a_q <= '0;
            a_valid_q <= 1'b0;
        end

        valid_pipe[0] <= a_valid_q;
        for (int k=1; k<VALID_LATENCY; k=k+1) begin
            valid_pipe[k] <= valid_pipe[k-1];
        end
    end
end

always_ff @(posedge i_clk) begin
    a_skew_data[0] <= a_q;
    for (int k=0; k<SKEW_STAGES; k=k+1) begin
        a_skew_data[k] <= a_skew_data[k-1];
    end
end

generate
    for (genvar lane=0; lane<N; lane=lane+1) begin : gen_activations
        if (lane ==0) begin : gen_lane_zero
            assign a_left[lane*DW +: DW] = a_q[lane*DW +: DW];
        end else begin : gen_lane_delayed
            assign a_left[lane*DW +: DW] = a_skew_data[lane-1][lane*DW +: DW];
        end
    end
endgenerate

array #(.N(N), .DW(DW), .ACC_W(ACC_W)) u_array (
    .i_clk     (i_clk),
    .i_load_en (weight_load_en),
    .i_w_top   (rd_rdata),
    .i_a_left  (a_left),
    .o_c_bottom(array_bottom)
);

generate
    for (genvar col=0; col<N; col=col+1) begin : gen_out_deskew
        if (col == N-1) begin : gen_last_col
            assign aligned_data[col*ACC_W +: ACC_W] = array_bottom[col*ACC_W +: ACC_W];
        end else begin : gen_delayed_col
            localparam int DELAY = N-1-col;
            logic signed [ACC_W-1:0] delay_line [0:DELAY-1];
            
            always_ff @(posedge i_clk) begin
                delay_line[0] <= array_bottom[col*ACC_W +: ACC_W];
                for (int k=1; k<DELAY; k=k+1) begin
                    delay_line[k] <= delay_line[k-1];
                end
            end
            assign aligned_data[col*ACC_W +: ACC_W] = delay_line[DELAY-1];
        end
    end
endgenerate

endmodule
`default_nettype wire
