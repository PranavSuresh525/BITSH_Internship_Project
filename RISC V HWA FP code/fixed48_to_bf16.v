`timescale 1ns / 1ps

// fixed48_to_bf16 -- 3-stage pipelined boundary converter
//
// Original version was a single combinational block: a 48-bit
// leading-zero-count (linear loop -> deep priority-encoder logic), a
// 48-bit dynamic normalizing left-shift, and rounding/packing, all in
// one shot sitting between the last systolic row's registered output
// and the output BRAM write. That's a second long combinational cone
// (independent of the PE's internal one) on the same boundary, and it
// runs once per output column every result cycle.
//
// This version pipelines it into 3 registered stages so the LZC and the
// normalizing shifter are each isolated between register boundaries
// (better timing, less glitch propagation -> less signal power):
//   S1: sign/abs-value + leading-zero-count, registered
//   S2: normalizing shift + exponent calc, registered
//   S3: rounding + packing, registered into bf16_out
//
// CONV_LATENCY (3 cycles, fix_in -> bf16_out) must match the constant of
// the same name assumed by dip_fsm.v's output-window timing -- if you
// change the pipeline depth here, update dip_fsm.v too.
module fixed48_to_bf16 #(
    parameter WIDTH = 48,
    parameter FRAC_BITS = 16
)(
    input  clk,
    input  rst,
    input  [WIDTH-1:0] fix_in,
    output reg [15:0] bf16_out
);

    localparam CONV_LATENCY = 3;

    // =====================================================================
    // Stage 1: sign/magnitude + leading-zero-count
    // =====================================================================
    wire              sign_comb    = fix_in[WIDTH-1];
    wire [WIDTH-1:0]  abs_val_comb = sign_comb ? -fix_in : fix_in;

    reg [5:0] lz_comb;
    integer i;
    always @(*) begin
        lz_comb = WIDTH;
        for (i = WIDTH-1; i >= 0; i = i - 1)
            if (abs_val_comb[i] && lz_comb == WIDTH) lz_comb = (WIDTH-1) - i;
    end

    reg              sign_s1;
    reg [WIDTH-1:0]  abs_val_s1;
    reg [5:0]        lz_s1;

    always @(posedge clk) begin
        if (rst) begin
            sign_s1    <= 1'b0;
            abs_val_s1 <= {WIDTH{1'b0}};
            lz_s1      <= 6'd0;
        end else begin
            sign_s1    <= sign_comb;
            abs_val_s1 <= abs_val_comb;
            lz_s1      <= lz_comb;
        end
    end

    // =====================================================================
    // Stage 2: normalizing shift + exponent
    // =====================================================================
    wire [WIDTH-1:0]  norm_val_comb = abs_val_s1 << lz_s1;
    wire signed [9:0] exp_comb = 10'sd127 + (WIDTH-1) - lz_s1 - FRAC_BITS;
    wire              is_zero_comb = (abs_val_s1 == 0);

    reg              sign_s2;
    reg              is_zero_s2;
    reg [WIDTH-1:0]  norm_val_s2;
    reg signed [9:0] exp_s2;

    always @(posedge clk) begin
        if (rst) begin
            sign_s2     <= 1'b0;
            is_zero_s2  <= 1'b0;
            norm_val_s2 <= {WIDTH{1'b0}};
            exp_s2      <= 10'sd0;
        end else begin
            sign_s2     <= sign_s1;
            is_zero_s2  <= is_zero_comb;
            norm_val_s2 <= norm_val_comb;
            exp_s2      <= exp_comb;
        end
    end

    // =====================================================================
    // Stage 3: round + pack
    // =====================================================================
    wire [7:0] final_exp_comb = (is_zero_s2 || exp_s2 <= 0) ? 8'd0 :
                                 (exp_s2 >= 255)             ? 8'd255 :
                                                                exp_s2[7:0];

    wire [6:0] mant_comb      = norm_val_s2[WIDTH-2 -: 7];
    wire       round_bit_comb = norm_val_s2[WIDTH-9];
    wire [7:0] rounded_mant_comb = {1'b0, mant_comb} + round_bit_comb;

    wire [7:0] final_mant_comb   = rounded_mant_comb[7] ? 7'd0 : rounded_mant_comb[6:0];
    wire [7:0] final_exp_r_comb  = rounded_mant_comb[7] ? final_exp_comb + 1 : final_exp_comb;

    wire [15:0] bf16_out_comb = is_zero_s2 ? 16'd0 : {sign_s2, final_exp_r_comb, final_mant_comb[6:0]};

    always @(posedge clk) begin
        if (rst) bf16_out <= 16'd0;
        else     bf16_out <= bf16_out_comb;
    end

endmodule