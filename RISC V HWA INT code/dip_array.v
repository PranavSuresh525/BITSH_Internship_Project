`timescale 1ns / 1ps
module dip_array #(
    parameter N = 8,
    parameter ACC_WIDTH = 32
) (
    input clk,
    input rst,
    input array_en,

    // ---- stationary weight load ----
    input                      load_en,
    input  [$clog2(N)-1:0]     load_row_idx,
    input  [N*16-1:0]          weight_bus_flat,

    // ---- new activation row, fed ONLY into row 0 ----
    input                      row0_valid,
    input  [N*16-1:0]          row0_act_bus_flat,

    // ---- final per-column result ----
    output [N*16-1:0]          result_flat,
    output                     array_out_valid
);

    // ── CLOCK GATING LOGIC ──
    wire clk_pe;
`ifdef __ICARUS__
    reg sim_gate_en;
    always @(negedge clk) begin
        if (rst) sim_gate_en <= 0;
        else     sim_gate_en <= array_en;
    end
    assign clk_pe = clk & sim_gate_en;
`else
    BUFGCE array_clk_gate (
        .I(clk), .CE(array_en), .O(clk_pe)
    );
`endif

    wire [N-1:0] row_clk;
    assign row_clk = {N{clk_pe}};

    wire [ACC_WIDTH-1:0] d_chain [0:N][0:N-1];

    wire [15:0] act_chain   [0:N][0:N-1];
    wire        valid_chain [0:N];

    wire [15:0] act_out_grid   [0:N-1][0:N-1];
    wire        valid_out_grid [0:N-1][0:N-1];

    // ---- Resync the clk-domain control bus into clk_pe, once ----
    reg                     load_en_pe;
    reg [$clog2(N)-1:0]     load_row_idx_pe;
    reg [N*16-1:0]          weight_bus_pe;
    reg                     row0_valid_pe;
    reg [N*16-1:0]          row0_act_bus_pe;

    always @(posedge clk_pe or posedge rst) begin
        if (rst) begin
            load_en_pe      <= 1'b0;
            load_row_idx_pe <= {$clog2(N){1'b0}};
            weight_bus_pe   <= {N*16{1'b0}};
            row0_valid_pe   <= 1'b0;
            row0_act_bus_pe <= {N*16{1'b0}};
        end else begin
            load_en_pe      <= load_en;
            load_row_idx_pe <= load_row_idx;
            weight_bus_pe   <= weight_bus_flat;
            row0_valid_pe   <= row0_valid;
            row0_act_bus_pe <= row0_act_bus_flat;
        end
    end

    genvar r, c;
    generate
        for (c = 0; c < N; c = c + 1) begin : COL_INIT
            assign d_chain[0][c]   = {ACC_WIDTH{1'b0}};
            assign act_chain[0][c] = row0_act_bus_pe[c*16 +: 16];
        end
    endgenerate

    assign valid_chain[0] = row0_valid_pe;

    generate
        for (r = 0; r < N; r = r + 1) begin : ROWS
            wire [31:0] r_wide = r;
            wire row_load_en = load_en_pe && (load_row_idx_pe == r_wide[$clog2(N)-1:0]);

            for (c = 0; c < N; c = c + 1) begin : COLS
                wire [15:0] w_in = weight_bus_pe[c*16 +: 16];

                pe #(
                    .ACC_WIDTH(ACC_WIDTH)
                ) u_pe (
                    .clk           (row_clk[r]),
                    .rst           (rst),
                    .weight_load_en(row_load_en),
                    .weight_in     (w_in),
                    .act_valid_in  (valid_chain[r]),
                    .act_in        (act_chain[r][c]),
                    .d_in          (d_chain[r][c]),
                    .act_valid_out (valid_out_grid[r][c]),
                    .act_out       (act_out_grid[r][c]),
                    .d_out         (d_chain[r+1][c])
                );
            end

            // diagonal hookup to next row
            for (c = 0; c < N; c = c + 1) begin : DIAG
                assign act_chain[r+1][c] = act_out_grid[r][(c+1)%N];
            end
            assign valid_chain[r+1] = valid_out_grid[r][0];
        end
    endgenerate

    // Single-cycle truncate-to-16-bit output register (the int
    // equivalent of the bf16 version's fixed48_to_bf16 converter).
    generate
        for (c = 0; c < N; c = c + 1) begin : FINAL_TRUNC
            reg [15:0] result_reg;
            always @(posedge clk_pe) begin
                if (rst) result_reg <= 16'd0;
                else if (array_en) result_reg <= d_chain[N][c][15:0];
            end
            assign result_flat[c*16 +: 16] = result_reg;
        end
    endgenerate

    // CONV_LATENCY = 1 (one register stage for the truncation above).
    reg valid_d;
    always @(posedge clk_pe) begin
        if (rst) valid_d <= 1'b0;
        else valid_d <= valid_chain[N];
    end
    assign array_out_valid = valid_d;

endmodule