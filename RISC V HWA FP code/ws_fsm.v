`timescale 1ns / 1ps

module ws_fsm #(
    parameter N = 16
) (
    input  clk,
    input  rst,
    input  start,

    output [N*$clog2(N)-1:0] weight_rd_addr_flat,
    input  [N*16-1:0]        weight_rd_data_flat,

    output [$clog2(N)-1:0]   input_rd_addr,
    input  [N*16-1:0]        input_rd_data_flat,

    output                   output_we,
    output [$clog2(N)-1:0]   output_wr_addr,
    output [N*16-1:0]        output_wr_data_flat,

    output                   load_en,
    output [$clog2(N)-1:0]   load_row_idx,
    output [N*16-1:0]        weight_bus_flat,
    output                   row0_valid,
    output [N*16-1:0]        row0_act_bus_flat,
    input  [N*16-1:0]        result_flat,
    input                    array_out_valid,

    output reg               busy,
    output reg               done
);

    localparam ADDR_W = $clog2(N);

    // Output write-back is driven entirely off array_out_valid (like
    // dip_fsm.v), not off a hardcoded cycle count. That makes it agnostic
    // to PE_LATENCY_PER_ROW / conversion pipeline depth inside ws_array.v --
    // no OUT_START/OUT_END bookkeeping needed, and nothing to keep in sync
    // if those latencies ever change.

    localparam ST_IDLE       = 2'd0;
    localparam ST_LOAD_RUN   = 2'd1;
    localparam ST_COMP_RUN   = 2'd2;

    reg [1:0] state;
    reg [ADDR_W+7:0] cyc; 

    reg [ADDR_W-1:0] w_issue_row;
    always @(*) begin
        if (state == ST_IDLE && start)       w_issue_row = {ADDR_W{1'b0}}; // Preload 0
        else if (state == ST_LOAD_RUN)       w_issue_row = (cyc[ADDR_W-1:0] + 1'b1);
        else                                 w_issue_row = {ADDR_W{1'b0}};
    end

    reg [$clog2(N):0] out_cnt;
    always @(posedge clk or posedge rst) begin
        if (rst) out_cnt <= 0;
        else if (state == ST_IDLE) out_cnt <= 0;
        else if (array_out_valid) out_cnt <= out_cnt + 1;
    end

    assign output_we           = array_out_valid;
    assign output_wr_addr      = out_cnt[$clog2(N)-1:0];
    assign output_wr_data_flat = result_flat;

    genvar gc;
    generate
        for (gc = 0; gc < N; gc = gc + 1) begin : WADDR
            // Removed the + gc offset. WS requires flat, unpermuted rows!
            assign weight_rd_addr_flat[gc*ADDR_W +: ADDR_W] = w_issue_row; 
        end
    endgenerate

    assign load_en         = (state == ST_LOAD_RUN);
    assign load_row_idx    = cyc[ADDR_W-1:0];
    assign weight_bus_flat = weight_rd_data_flat;

    reg [ADDR_W-1:0] i_issue_row;
    always @(*) begin
        if (state == ST_LOAD_RUN && cyc == N-1) i_issue_row = {ADDR_W{1'b0}}; // Preload 0
        else if (state == ST_COMP_RUN)          i_issue_row = (cyc[ADDR_W-1:0] + 1'b1);
        else                                    i_issue_row = {ADDR_W{1'b0}};
    end
    assign input_rd_addr = i_issue_row;

    assign row0_valid        = (state == ST_COMP_RUN) && (cyc < N);
    assign row0_act_bus_flat = input_rd_data_flat;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= ST_IDLE;
            cyc   <= 0;
            busy  <= 1'b0;
            done  <= 1'b0;
        end else begin
            done <= 1'b0; 

            case (state)
                ST_IDLE: begin
                    if (start) begin
                        state <= ST_LOAD_RUN;
                        cyc   <= 0;
                        busy  <= 1'b1;
                    end
                end

                ST_LOAD_RUN: begin
                    if (cyc == N-1) begin
                        state <= ST_COMP_RUN;
                        cyc   <= 0;
                    end else begin
                        cyc <= cyc + 1;
                    end
                end

                ST_COMP_RUN: begin
                    if (array_out_valid && out_cnt == N-1) begin
                        state <= ST_IDLE; 
                        done  <= 1'b1;
                        busy  <= 1'b0;
                    end else begin
                        cyc <= cyc + 1;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule