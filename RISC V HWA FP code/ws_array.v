`timescale 1ns / 1ps

module ws_array #(
    parameter N = 32,
    parameter ACC_WIDTH = 32, 
    parameter FRAC_BITS = 16,
    parameter PE_LATENCY_PER_ROW = 1
) (
    input clk,
    input rst,
    input array_en, 
    
    input                                  load_en,
    input  [$clog2(N)-1:0]                 load_row_idx,
    input  [N*16-1:0]                      weight_bus_flat, 

    input                                  row0_valid,
    input  [N*16-1:0]                      row0_act_bus_flat, 

    output [N*16-1:0]                      result_flat,
    output                                 array_out_valid 
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

    // ONLY a single 32-bit chain now
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

    // ── INPUT FIFOs ──
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

    // ── PE GRID ──
    generate
        for (r = 0; r < N; r = r + 1) begin : ROWS
            wire row_load_en = load_en && (load_row_idx == r[$clog2(N)-1:0]);
            for (c = 0; c < N; c = c + 1) begin : COLS
                wire [15:0] w_in  = weight_bus_flat[c*16 +: 16];
                
                pe_bf16 #(
                    .ACC_WIDTH(ACC_WIDTH),
                    .FRAC_BITS(FRAC_BITS)
                ) u_pe (
                    .clk(row_clk[r]), 
                    .rst(rst),
                    .weight_load_en(row_load_en),
                    .weight_in(w_in),
                    .act_valid_in(valid_chain[r][c]),
                    .act_in(act_chain[r][c]),
                    .d_in(d_chain[r][c]),  
                    .act_valid_out(valid_out_grid[r][c]),
                    .act_out(act_out_grid[r][c]),
                    .d_out(d_chain[r+1][c]) 
                );
                
                // HORIZONTAL wiring for activations (Left to Right)
                assign act_chain[r][c+1]   = act_out_grid[r][c];
                assign valid_chain[r][c+1] = valid_out_grid[r][c];
            end
        end
    endgenerate

    // ── OUTPUT FIFOs AND INLINE BOUNDARY CONVERSION ──
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

            // 4-STAGE PIPELINED BF16 CONVERSION
            reg stage1_sign;
            reg [ACC_WIDTH-1:0] stage1_abs_val;
            
            reg stage2_sign;
            reg [ACC_WIDTH-1:0] stage2_abs_val;
            reg [5:0] stage2_lz;
            
            reg stage3_sign;
            reg [ACC_WIDTH-1:0] stage3_abs_val;
            reg [ACC_WIDTH-1:0] stage3_norm_val;
            reg signed [9:0] stage3_fixed_exp;
            
            reg [15:0] stage4_result;

            // Use the same clock as the output FIFO
`ifdef __ICARUS__
            wire conv_clk = clk_pe;
`else
            wire conv_clk = row_clk[N-1]; 
`endif

            integer i;
            reg [5:0] temp_lz;

            always @(posedge conv_clk) begin
                if (rst) begin
                    stage4_result <= 16'd0;
                end else if (array_en) begin
                    

                    // STAGE 1: Sign extraction and Absolute Value

                    stage1_sign    <= packed_sums_out[ACC_WIDTH-1];
                    stage1_abs_val <= packed_sums_out[ACC_WIDTH-1] ? -packed_sums_out : packed_sums_out;
                    

                    // STAGE 2: Leading Zero Count

                    stage2_sign    <= stage1_sign;
                    stage2_abs_val <= stage1_abs_val;
                    
                    temp_lz = ACC_WIDTH;
                    for (i = ACC_WIDTH-1; i >= 0; i = i - 1) begin
                        if (stage1_abs_val[i] && temp_lz == ACC_WIDTH) temp_lz = (ACC_WIDTH-1) - i;
                    end
                    stage2_lz <= temp_lz;


                    // STAGE 3: Normalization and Base Exponent

                    stage3_sign      <= stage2_sign;
                    stage3_abs_val   <= stage2_abs_val;
                    stage3_norm_val  <= stage2_abs_val << stage2_lz;
                    stage3_fixed_exp <= 10'sd127 + (ACC_WIDTH-1) - stage2_lz - FRAC_BITS;

                    // STAGE 4: Rounding, Clamping, and Packing

                    if (stage3_abs_val == 0) begin
                        stage4_result <= 16'd0;
                    end else begin
                        reg [7:0] t_exp;
                        reg [7:0] t_rounded_mant;
                        
                        t_exp = (stage3_fixed_exp <= 0) ? 8'd0 : 
                                (stage3_fixed_exp >= 255) ? 8'd255 : stage3_fixed_exp[7:0];
                        
                        t_rounded_mant = {1'b0, stage3_norm_val[30:24]} + stage3_norm_val[23];
                        
                        if (t_rounded_mant[7]) begin
                            stage4_result <= {stage3_sign, t_exp + 8'd1, 7'd0};
                        end else begin
                            stage4_result <= {stage3_sign, t_exp, t_rounded_mant[6:0]};
                        end
                    end
                end
            end

            assign result_flat[p*16 +: 16] = stage4_result;
        end
    endgenerate

reg [3:0] conv_valid_pipe;
always @(posedge clk_pe) begin
    if (rst) conv_valid_pipe <= 0;
    else if (array_en) conv_valid_pipe <= {conv_valid_pipe[2:0], valid_out_grid[N-1][N-1]};
end
assign array_out_valid = conv_valid_pipe[3];

endmodule