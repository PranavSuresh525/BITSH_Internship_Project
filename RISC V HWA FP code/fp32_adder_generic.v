`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// fp32_adder_generic
//
// FP32 version of bf16_adder_generic.v: full add/sub adder, used here once
// per output column to combine the two FP32 sign-separated sub-
// accumulations (d, d2) into the final FP32 accumulator value (which then
// gets rounded down to BF16 by fp32_to_bf16.v for output).
//
// Same-sign operands are handled by the cheap fp32_samesign_adder; only
// opposite-sign operands pay for the leading-zero-detect + left-shift
// renormalization. The LZC here uses a small loop-based function rather
// than a hand-written casez table (the BF16 version's 8-bit table was
// already a little error-prone to write by hand; at 24 bits it would be
// much more so) -- functionally identical, just safer to get right.
//////////////////////////////////////////////////////////////////////////////
module fp32_adder_generic (
    input  [31:0] a,
    input  [31:0] b,
    output [31:0] result
);

    wire same_sign = (a[31] == b[31]);

    //------------------------------------------------------------------
    // cheap path: same sign -> reuse the resource-efficient adder
    //------------------------------------------------------------------
    wire [31:0] samesign_result;
    fp32_samesign_adder u_ss (.a(a), .b(b), .result(samesign_result));

    //------------------------------------------------------------------
    // expensive path: opposite signs -> true subtraction of magnitudes
    //------------------------------------------------------------------
    wire [7:0]  exp_a = a[30:23];
    wire [7:0]  exp_b = b[30:23];
    wire [22:0] man_a = a[22:0];
    wire [22:0] man_b = b[22:0];
    wire a_zero = (exp_a == 8'd0);
    wire b_zero = (exp_b == 8'd0);

    wire a_mag_ge_b = (exp_a > exp_b) || ((exp_a == exp_b) && (man_a >= man_b));

    wire        dom_sign   = a_mag_ge_b ? a[31] : b[31];
    wire [7:0]  exp_dom    = a_mag_ge_b ? exp_a : exp_b;
    wire [23:0] sig_dom    = a_mag_ge_b ? {1'b1, man_a} : {1'b1, man_b};
    wire [23:0] sig_nondom = a_mag_ge_b ? {1'b1, man_b} : {1'b1, man_a};
    wire [7:0]  exp_diff   = a_mag_ge_b ? (exp_a - exp_b) : (exp_b - exp_a);

    localparam SHMAX = 48;
    wire [7:0]  shamt        = (exp_diff > SHMAX) ? SHMAX[7:0] : exp_diff;
    wire        shift_excess = (exp_diff > SHMAX) & (|sig_nondom);
    wire [71:0] nondom_ext   = {sig_nondom, 48'b0};
    wire [71:0] shifted      = nondom_ext >> shamt;
    wire [23:0] mant_nondom_aligned = shifted[71:48];
    wire        g1 = shifted[47];
    wire        r1 = shifted[46];
    wire        s1 = (|shifted[45:0]) | shift_excess;

    wire borrow_in = (g1 | r1 | s1);
    (* use_dsp = "yes" *)wire [24:0] mant_diff25 = {1'b0, sig_dom} - {1'b0, mant_nondom_aligned} - (borrow_in ? 25'd1 : 25'd0);
    wire g1b, r1b, s1b;
    assign g1b = borrow_in ? ~g1 : g1;
    assign r1b = borrow_in ? ~r1 : r1;
    assign s1b = borrow_in ? ~s1 : s1;

    wire [23:0] mant_diff = mant_diff25[23:0]; // bit24 should be 0 given correct dominant selection

    // leading-zero count over 24 bits (0..24, 24 meaning "all zero")
    function [4:0] clz24;
        input [23:0] val;
        integer k;
        begin
            clz24 = 24;
            for (k = 23; k >= 0; k = k - 1)
                if (val[k] && (clz24 == 24)) clz24 = 23 - k;
        end
    endfunction

    wire [4:0] lzc = clz24(mant_diff);
    wire       is_true_zero = (lzc == 24);

    // shift the {mantissa, g1b, r1b, s1b} bucket left by lzc, with plenty
    // of zero headroom below (see fp32_samesign_adder.v's header for why
    // 2*SIGW-ish margin is enough; using a generous 64 bits here)
    wire [63:0] diff_ext     = {mant_diff, g1b, r1b, s1b, 37'b0};
    wire [63:0] diff_shifted = diff_ext << lzc;
    wire [23:0] mant_norm24  = diff_shifted[63:40];
    wire        g2 = diff_shifted[39];
    wire        r2 = diff_shifted[38];
    wire        s2 = |diff_shifted[37:0];

    wire signed [9:0] exp_norm = $signed({2'b0, exp_dom}) - {5'b0, lzc};

    wire round_up = g2 & (r2 | s2 | mant_norm24[0]);
    wire [24:0] mant_rounded = {1'b0, mant_norm24} + (round_up ? 25'd1 : 25'd0);
    wire        mant_ovf = mant_rounded[24];
    wire [23:0] mant_final24 = mant_ovf ? {1'b1, 23'b0} : mant_rounded[23:0];
    wire signed [9:0] exp_final = exp_norm + (mant_ovf ? 10'sd1 : 10'sd0);

    wire underflow = (exp_final <= 0);

    wire [31:0] sub_result = is_true_zero ? 32'd0 :
                              underflow    ? {dom_sign, 31'd0} :
                                             {dom_sign, exp_final[7:0], mant_final24[22:0]};

    wire [31:0] diffsign_result = a_zero ? b :
                                  b_zero ? a :
                                           sub_result;

    assign result = (a_zero & b_zero) ? {a[31] & b[31], 31'd0} :
                    same_sign         ? samesign_result :
                                        diffsign_result;

endmodule
