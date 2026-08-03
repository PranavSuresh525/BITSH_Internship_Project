`timescale 1ns / 1ps

// dip_fsm -- updated for the pipelined pe_bf16 / fixed48_to_bf16.
//
// TIMING CHANGE FROM THE ORIGINAL VERSION:
// pe_bf16 used to take 1 clock cycle to pass data from one systolic row
// to the next; it now takes PE_LATENCY_PER_ROW (=3) cycles, because the
// multiply/cast/accumulate datapath inside each PE was split into a
// 3-stage pipeline to fix a timing-critical combinational cone (and cut
// glitch power). fixed48_to_bf16 at the array's output boundary was
// likewise split into a 3-stage pipeline (CONV_LATENCY = 3).
//
// Consequently the last row0-injected activation (issued at cyc = N-1)
// now takes N*PE_LATENCY_PER_ROW cycles to reach the final row, plus
// CONV_LATENCY more to clear the output converter, before its result is
// valid -- vs. just N cycles in the original 1-cycle-per-row design.
// The output-write window and the state's end-of-compute cycle are
// derived below instead of hardcoded, so this scales automatically if
// N or the pipeline depths change (just keep PE_LATENCY_PER_ROW /
// CONV_LATENCY here in sync with pe_bf16.v / fixed48_to_bf16.v).
module dip_fsm #(
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
    input array_out_valid,

    output reg               busy,
    output reg               done
);

    localparam ADDR_W = $clog2(N);

    localparam ST_IDLE       = 2'd0;
    localparam ST_LOAD_RUN   = 2'd1;
    localparam ST_COMP_RUN   = 2'd2;

    reg [1:0] state;
    reg [ADDR_W+3:0] cyc;
    
    reg [$clog2(N):0] out_cnt;
    always @(posedge clk or posedge rst) begin
        if (rst) out_cnt <= 0;
        else if (state == ST_IDLE) out_cnt <= 0;
        else if (array_out_valid) out_cnt <= out_cnt + 1;
    end

    // Direct write mapping based entirely on array output valid
    assign output_we           = array_out_valid;
    assign output_wr_addr      = out_cnt[$clog2(N)-1:0];

    reg [ADDR_W-1:0] w_issue_row;
    always @(*) begin
        if (state == ST_IDLE && start)       w_issue_row = 0;
        else if (state == ST_LOAD_RUN)       w_issue_row = (cyc[ADDR_W-1:0] + 1) % N;
        else                                 w_issue_row = 0;
    end


    genvar gc;
    generate
        for (gc = 0; gc < N; gc = gc + 1) begin : WADDR
            assign weight_rd_addr_flat[gc*ADDR_W +: ADDR_W] = (w_issue_row + gc) % N;
        end
    endgenerate

    assign load_en         = (state == ST_LOAD_RUN);
    assign load_row_idx    = cyc[ADDR_W-1:0];
    assign weight_bus_flat = weight_rd_data_flat;

    reg [ADDR_W-1:0] i_issue_row;
    always @(*) begin
        if (state == ST_LOAD_RUN && cyc[ADDR_W-1:0] == N-1) i_issue_row = 0;
        else if (state == ST_COMP_RUN)                      i_issue_row = (cyc[ADDR_W-1:0] + 1) % N;
        else                                                i_issue_row = 0;
    end

    assign input_rd_addr = (state == ST_COMP_RUN) ? i_issue_row : 0;

    assign row0_valid        = (state == ST_COMP_RUN) && (cyc < N);
    assign row0_act_bus_flat = row0_valid ? input_rd_data_flat : {N*16{1'b0}};

    assign output_wr_data_flat = result_flat;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= ST_IDLE;
            cyc   <= 0;
            busy  <= 1'b0;
            done  <= 1'b0;
        end else begin
            // Pulse done for 1 cycle, then auto-clear
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
                        cyc <= cyc + 1'b1;
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