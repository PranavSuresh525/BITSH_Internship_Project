`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// fp32_samesign_adder
//
// FP32 version of bf16_samesign_adder.v -- same SEA same-signed-adder
// algorithm (Algorithm 1 in the SEA paper, add-only path, at most a
// single right shift to renormalize), just at the wider 23-bit mantissa
// width used for the accumulator side of the aFP32mBF16 mixed-precision
// scheme. See bf16_samesign_adder.v for the detailed derivation; widths
// below are scaled 1:1 (M=23 instead of M=7).
//
// PRECONDITION: sign(a) == sign(b) (or either operand is +0/-0).
//////////////////////////////////////////////////////////////////////////////
module fp32_samesign_adder (
    input  [31:0] a,
    input  [31:0] b,
    output [31:0] result
);

    wire        sign_r = a[31]; // == b[31] by precondition
    wire [7:0]  exp_a  = a[30:23];
    wire [7:0]  exp_b  = b[30:23];
    wire [22:0] man_a  = a[22:0];
    wire [22:0] man_b  = b[22:0];

    wire a_zero = (exp_a == 8'd0);
    wire b_zero = (exp_b == 8'd0);

    //------------------------------------------------------------------
    // Stage 1 : pick dominant (larger-exponent) operand
    //------------------------------------------------------------------
    wire a_ge_b = (exp_a >= exp_b);
    wire [7:0]  exp_dom    = a_ge_b ? exp_a : exp_b;
    wire [23:0] sig_dom    = a_ge_b ? {1'b1, man_a} : {1'b1, man_b};
    wire [23:0] sig_nondom = a_ge_b ? {1'b1, man_b} : {1'b1, man_a};
    wire [7:0]  exp_diff   = a_ge_b ? (exp_a - exp_b) : (exp_b - exp_a);

    //------------------------------------------------------------------
    // Stage 2 : VRSH - variable right shift of non-dominant mantissa,
    //           generate guard/round/sticky bits
    //------------------------------------------------------------------
    localparam SHMAX = 48;
    wire [7:0]  shamt        = (exp_diff > SHMAX) ? SHMAX[7:0] : exp_diff;
    wire        shift_excess = (exp_diff > SHMAX) & (|sig_nondom);
    wire [71:0] nondom_ext   = {sig_nondom, 48'b0};
    wire [71:0] shifted      = nondom_ext >> shamt;

    wire [23:0] mant_nondom_aligned = shifted[71:48];
    wire        g1 = shifted[47];
    wire        r1 = shifted[46];
    wire        s1 = (|shifted[45:0]) | shift_excess;

    //------------------------------------------------------------------
    // Stage 3 : mantissa ADD (unconditional, same sign)
    //------------------------------------------------------------------
    (* use_dsp = "yes" *)wire [24:0] mant_sum = {1'b0, sig_dom} + {1'b0, mant_nondom_aligned};
    //------------------------------------------------------------------
    // Stage 4 : normalize -- at most ONE right shift needed
    //------------------------------------------------------------------
    wire        shift_norm  = mant_sum[24];
    wire [23:0] mant_norm24 = shift_norm ? mant_sum[24:1] : mant_sum[23:0];
    wire        g2 = shift_norm ? mant_sum[0] : g1;
    wire        r2 = shift_norm ? g1          : r1;
    wire        s2 = shift_norm ? (r1 | s1)   : s1;
    wire [7:0]  exp_pre = exp_dom + (shift_norm ? 8'd1 : 8'd0);

    //------------------------------------------------------------------
    // Stage 5 : round to nearest, ties to even
    //------------------------------------------------------------------
    wire round_up = g2 & (r2 | s2 | mant_norm24[0]);
    wire [24:0] mant_rounded = {1'b0, mant_norm24} + (round_up ? 25'd1 : 25'd0);
    wire        mant_ovf    = mant_rounded[24];
    wire [23:0] mant_final24 = mant_ovf ? {1'b1, 23'b0} : mant_rounded[23:0];
    wire [7:0]  exp_final    = exp_pre + (mant_ovf ? 8'd1 : 8'd0);

    wire [31:0] sum_result = {sign_r, exp_final, mant_final24[22:0]};

    assign result = a_zero ? b :
                    b_zero ? a :
                             sum_result;

endmodule
