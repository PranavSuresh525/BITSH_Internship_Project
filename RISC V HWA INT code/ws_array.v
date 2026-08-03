`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// ws_array (integer / fixed-point version)
//
// Structurally identical to the decimal ws_array.v: same clock gating,
// same direct weight broadcast + load_row_idx addressing (no shift-through
// weight load), same per-PE act_valid_in/act_valid_out chain with row-skew
// input FIFOs, same output-FIFO column realignment scheme. The only
// difference is the final per-column output stage: a single-cycle
// truncate-to-16-bit register instead of the 4-stage bf16 pack/round
// pipeline (there is no float format to convert to here, so
// CONV_LATENCY = 1 instead of 4).
//////////////////////////////////////////////////////////////////////////////
module ws_array #(
    parameter N = 8,
    parameter ACC_WIDTH = 32,
    // MUST match pe.v's act_valid_in -> act_valid_out latency. Every
    // row-skew / output-skew FIFO below is stretched by this factor.
    parameter PE_LATENCY_PER_ROW = 1
) (
    input clk,
    input rst,
    input array_en,

    input                      load_en,
    input  [$clog2(N)-1:0]     load_row_idx,
    input  [N*16-1:0]          weight_bus_flat,

    input                      row0_valid,
    input  [N*16-1:0]          row0_act_bus_flat,

    output [N*16-1:0]          result_flat,
    output                     array_out_valid
);

    // ── CLOCK GATING LOGIC ──
    wire clk_pe;
`ifdef __ICARUS__
    reg sim_gate_en;
    always @(negedge clk) begin
        if (rst) sim_gate_en <= 0;
        else sim_gate_en <= array_en;
    end
    assign clk_pe = clk & sim_gate_en;
    wire [N-1:0] row_clk;
    assign row_clk = {N{clk_pe}};
`else
    BUFGCE array_clk_gate (
        .I(clk), .CE(array_en), .O(clk_pe)
    );
    wire [N-1:0] row_clk;
    assign row_clk = {N{clk_pe}};
`endif

    wire [ACC_WIDTH-1:0] d_chain [0:N][0:N-1];

    wire [15:0] act_chain   [0:N-1][0:N];
    wire        valid_chain [0:N-1][0:N];

    wire [15:0] act_out_grid   [0:N-1][0:N-1];
    wire        valid_out_grid [0:N-1][0:N-1];

    genvar r, c, p;

    // ── INITIALIZATION ──
    generate
        for (c = 0; c < N; c = c + 1) begin : COL_INIT
            assign d_chain[0][c] = {ACC_WIDTH{1'b0}};
        end
    endgenerate

    // ── INPUT FIFOs (row skew) ──
    generate
        for (r = 0; r < N; r = r + 1) begin : fifo_in_gen
`ifdef __ICARUS__
            wire clk_fifo_in = clk_pe;
`else
            wire clk_fifo_in = clk;
`endif
            if (r == 0) begin : r0
                assign act_chain[0][0]   = row0_act_bus_flat[0 +: 16];
                assign valid_chain[0][0] = row0_valid;
            end else begin : r_other
                localparam DLY = r * PE_LATENCY_PER_ROW;
                fifo #(.DEPTH(DLY), .WIDTH(16)) in_fifo (
                    .clk     (clk_fifo_in),
                    .rst     (rst),
                    .en      (array_en),
                    .data_in (row0_act_bus_flat[r*16 +: 16]),
                    .data_out(act_chain[r][0])
                );
                if (DLY == 1) begin : V_DELAY_1
                    reg v_delay;
                    always @(posedge clk_fifo_in) begin
                        if (rst) v_delay <= 1'b0;
                        else if (array_en) v_delay <= row0_valid;
                    end
                    assign valid_chain[r][0] = v_delay;
                end else begin : V_DELAY_N
                    reg [DLY-1:0] v_delay;
                    always @(posedge clk_fifo_in) begin
                        if (rst) v_delay <= {DLY{1'b0}};
                        else if (array_en) v_delay <= {v_delay[DLY-2:0], row0_valid};
                    end
                    assign valid_chain[r][0] = v_delay[DLY-1];
                end
            end
        end
    endgenerate

    // ── PE GRID (direct weight broadcast, addressed by load_row_idx) ──
    generate
        for (r = 0; r < N; r = r + 1) begin : ROWS
            wire row_load_en = load_en && (load_row_idx == r[$clog2(N)-1:0]);
            for (c = 0; c < N; c = c + 1) begin : COLS
                wire [15:0] w_in = weight_bus_flat[c*16 +: 16];

                pe #(
                    .ACC_WIDTH(ACC_WIDTH)
                ) u_pe (
                    .clk           (row_clk[r]),
                    .rst           (rst),
                    .weight_load_en(row_load_en),
                    .weight_in     (w_in),
                    .act_valid_in  (valid_chain[r][c]),
                    .act_in        (act_chain[r][c]),
                    .d_in          (d_chain[r][c]),
                    .act_valid_out (valid_out_grid[r][c]),
                    .act_out       (act_out_grid[r][c]),
                    .d_out         (d_chain[r+1][c])
                );

                // HORIZONTAL wiring for activations (Left to Right)
                assign act_chain[r][c+1]   = act_out_grid[r][c];
                assign valid_chain[r][c+1] = valid_out_grid[r][c];
            end
        end
    endgenerate

    // ── OUTPUT FIFOs AND INLINE TRUNCATION ──
    generate
        for (p = 0; p < N; p = p + 1) begin : out_pipeline

            wire [ACC_WIDTH-1:0] packed_sums_out;

            if (p == N-1) begin : last_col
                assign packed_sums_out = d_chain[N][p];
            end else begin : other_cols
`ifdef __ICARUS__
                wire clk_fifo_out = clk_pe;
`else
                wire clk_fifo_out = row_clk[N-1];
`endif
                fifo #(.DEPTH((N-1-p)*PE_LATENCY_PER_ROW), .WIDTH(ACC_WIDTH)) out_fifo (
                    .clk     (clk_fifo_out),
                    .rst     (rst),
                    .en      (array_en),
                    .data_in (d_chain[N][p]),
                    .data_out(packed_sums_out)
                );
            end

            // Single-cycle truncate-to-16-bit output register (the int
            // equivalent of the bf16 version's 4-stage pack/round pipeline).
`ifdef __ICARUS__
            wire conv_clk = clk_pe;
`else
            wire conv_clk = row_clk[N-1];
`endif
            reg [15:0] result_reg;
            always @(posedge conv_clk) begin
                if (rst) result_reg <= 16'd0;
                else if (array_en) result_reg <= packed_sums_out[15:0];
            end
            assign result_flat[p*16 +: 16] = result_reg;
        end
    endgenerate

    // CONV_LATENCY = 1 (one register stage for the truncation above).
    reg conv_valid_pipe;
    always @(posedge clk_pe) begin
        if (rst) conv_valid_pipe <= 1'b0;
        else if (array_en) conv_valid_pipe <= valid_out_grid[N-1][N-1];
    end
    assign array_out_valid = conv_valid_pipe;

endmodule