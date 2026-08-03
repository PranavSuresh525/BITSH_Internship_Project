`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// ALU.v  –  Integer + FP32 ALU
//
// Integer control codes (unchanged):
//   0  = ADD       1  = SUB       2  = XOR
//   3  = OR        4  = AND       5  = SLL
//   6  = SRL       7  = SRA       8  = SLT (signed)
//   9  = SLTU      10 = pass-A (for branch-offset / JAL)
//
// FP32 control codes (new):
//   11 = FADD.S    12 = FSUB.S   13 = FMUL.S
//   14 = FMIN.S    15 = FMAX.S
//   16 = FEQ.S     17 = FLT.S    18 = FLE.S
//   19 = FCVT.W.S  (FP32 -> signed int, round-to-zero)
//   20 = FCVT.S.W  (signed int -> FP32)
//   21 = FMV.X.W   (bitwise move FP reg -> int reg)
//   22 = FMV.W.X   (bitwise move int reg -> FP reg)
//   23 = FSGNJ.S   24 = FSGNJN.S  25 = FSGNJX.S
//////////////////////////////////////////////////////////////////////////////////
module ALU (
    input  [31:0] a,        // ALU input 1
    input  [31:0] b,        // ALU input 2
    input  [4:0]  control,  // widened to 5 bits
    output reg [31:0] c     // result
);

    // ----------------------------------------------------------------
    // FP32 add/sub combinational results
    // ----------------------------------------------------------------
    wire [31:0] fp_add_result, fp_sub_b, fp_sub_result, fp_mul_result;

    fp32_adder_generic u_fadd (
        .a(a),
        .b(b),
        .result(fp_add_result)
    );

    // FSUB: negate sign of b, then add
    assign fp_sub_b = {~b[31], b[30:0]};

    fp32_adder_generic u_fsub (
        .a(a),
        .b(fp_sub_b),
        .result(fp_sub_result)
    );

    // FMUL.S: reuse bf16_mul_fp32-style logic at FP32 width
    fp32_multiplier u_fmul (
        .a(a),
        .b(b),
        .result(fp_mul_result)
    );

    wire        sign_a   = a[31];
    wire        sign_b   = b[31];
    wire [7:0]  exp_a    = a[30:23];
    wire [7:0]  exp_b    = b[30:23];
    wire [22:0] man_a    = a[22:0];
    wire [22:0] man_b    = b[22:0];
    wire        a_is_nan = (&exp_a) & (|man_a);
    wire        b_is_nan = (&exp_b) & (|man_b);

    // a < b in IEEE 754 sense (handles signs correctly)
    wire fp_lt;
    assign fp_lt = (!sign_a &&  sign_b) ? 1'b0 :   // a pos, b neg -> a > b
                   ( sign_a && !sign_b) ? 1'b1 :   // a neg, b pos -> a < b
                   (!sign_a && !sign_b) ?           // both positive
                       ({exp_a, man_a} < {exp_b, man_b}) :
                       ({exp_a, man_a} > {exp_b, man_b}); // both negative, flipped

    wire fp_eq = (a == b) || ((a[30:0] == 0) && (b[30:0] == 0)); // ±0 == ±0

    wire [31:0] fcvt_w_s;
    fp32_to_int u_fcvt (.a(a), .result(fcvt_w_s));

    wire [31:0] fcvt_s_w;
    int_to_fp32 u_itof (.a(a), .result(fcvt_s_w));

    always @(*) begin
        case (control)
            // --- Integer ---
            5'd0:  c = a + b;
            5'd1:  c = a - b;
            5'd2:  c = a ^ b;
            5'd3:  c = a | b;
            5'd4:  c = a & b;
            5'd5:  c = a << b[4:0];
            5'd6:  c = a >> b[4:0];
            5'd7:  c = $signed(a) >>> b[4:0];
            5'd8:  c = ($signed(a) < $signed(b)) ? 32'd1 : 32'd0;
            5'd9:  c = (a < b) ? 32'd1 : 32'd0;
            5'd10: c = a;           // pass-through (JAL/AUIPC intermediate)

            // --- FP32 arithmetic ---
            5'd11: c = fp_add_result;   // FADD.S
            5'd12: c = fp_sub_result;   // FSUB.S
            5'd13: c = fp_mul_result;   // FMUL.S

            // --- FP32 min/max (IEEE 754-2008: NaN propagation) ---
            5'd14: c = a_is_nan ? b :   // FMIN.S
                       b_is_nan ? a :
                       fp_lt    ? a : b;
            5'd15: c = a_is_nan ? b :   // FMAX.S
                       b_is_nan ? a :
                       fp_lt    ? b : a;

            // --- FP32 comparisons (return 0 or 1 as integer) ---
            5'd16: c = (a_is_nan | b_is_nan) ? 32'd0 : (fp_eq  ? 32'd1 : 32'd0); // FEQ.S
            5'd17: c = (a_is_nan | b_is_nan) ? 32'd0 : (fp_lt  ? 32'd1 : 32'd0); // FLT.S
            5'd18: c = (a_is_nan | b_is_nan) ? 32'd0 : ((fp_lt | fp_eq) ? 32'd1 : 32'd0); // FLE.S

            // --- FP32 <-> int conversions ---
            5'd19: c = fcvt_w_s;        // FCVT.W.S
            5'd20: c = fcvt_s_w;        // FCVT.S.W

            // --- Bitwise moves (no conversion) ---
            5'd21: c = a;               // FMV.X.W  (bits pass straight through)
            5'd22: c = a;               // FMV.W.X

            // --- Sign-injection ---
            5'd23: c = {b[31],        a[30:0]}; // FSGNJ.S
            5'd24: c = {~b[31],       a[30:0]}; // FSGNJN.S
            5'd25: c = {a[31]^b[31],  a[30:0]}; // FSGNJX.S

            default: c = 32'd0;
        endcase
    end

endmodule


module fp32_multiplier (
    input  [31:0] a,
    input  [31:0] b,
    output [31:0] result
);
    wire        sign_r = a[31] ^ b[31];
    wire [7:0]  exp_a  = a[30:23];
    wire [7:0]  exp_b  = b[30:23];
    wire [22:0] man_a  = a[22:0];
    wire [22:0] man_b  = b[22:0];

    wire a_zero = (exp_a == 8'd0);
    wire b_zero = (exp_b == 8'd0);
    wire a_inf  = (&exp_a) & ~(|man_a);
    wire b_inf  = (&exp_b) & ~(|man_b);
    wire a_nan  = (&exp_a) &  (|man_a);
    wire b_nan  = (&exp_b) &  (|man_b);

    // 24x24 mantissa product (bit 47 or 46 is implicit-1 result)
    wire [47:0] prod = {1'b1, man_a} * {1'b1, man_b};

    // Unbiased exponent sum
    wire signed [9:0] exp_sum = $signed({2'b0, exp_a}) + $signed({2'b0, exp_b}) - 10'sd127;

    wire        shift1   = prod[47];
    wire signed [9:0] exp_adj = exp_sum + (shift1 ? 10'sd1 : 10'sd0);

    // Extract 23-bit mantissa + GRS bits
    wire [22:0] mant23  = shift1 ? prod[46:24] : prod[45:23];
    wire        g_bit   = shift1 ? prod[23]    : prod[22];
    wire        r_bit   = shift1 ? prod[22]    : prod[21];
    wire        s_bit   = shift1 ? (|prod[21:0]) : (|prod[20:0]);

    wire round_up = g_bit & (r_bit | s_bit | mant23[0]);
    wire [23:0] mant_rounded = {1'b0, mant23} + (round_up ? 24'd1 : 24'd0);
    wire        mant_ovf     = mant_rounded[23];
    wire [22:0] mant_final   = mant_ovf ? mant_rounded[22:0] : mant_rounded[22:0];
    wire signed [9:0] exp_final = exp_adj + (mant_ovf ? 10'sd1 : 10'sd0);

    wire underflow = (exp_final <= 10'sd0);
    wire overflow  = (exp_final >= 10'sd255);

    assign result = a_nan | b_nan                ? {1'b0, 8'hFF, 23'h400000} : // canonical NaN
                    (a_zero & b_inf) | (a_inf & b_zero) ? {1'b0, 8'hFF, 23'h400000} : // inf*0 = NaN
                    (a_inf | b_inf)              ? {sign_r, 8'hFF, 23'd0}   : // inf
                    (a_zero | b_zero)            ? {sign_r, 31'd0}          : // zero
                    underflow                    ? {sign_r, 31'd0}          :
                    overflow                     ? {sign_r, 8'hFE, 23'h7FFFFF} :
                                                   {sign_r, exp_final[7:0], mant_final};
endmodule


module fp32_to_int (
    input  [31:0] a,
    output [31:0] result
);
    wire        sign = a[31];
    wire [7:0]  exp  = a[30:23];
    wire [22:0] man  = a[22:0];

    wire is_nan  = (&exp) &  (|man);
    wire is_inf  = (&exp) & ~(|man);
    wire is_zero = (exp == 8'd0);

    // Unbiased exponent
    wire signed [8:0] e = $signed({1'b0, exp}) - 9'sd127;

    // Shifted significand: {1,man} left by (e-23)
    // For e < 0 -> result is 0; for e >= 31 -> saturate
    wire [54:0] sig_ext = {1'b1, man, 31'b0};       // 1.man in Q1.54 form
    wire [4:0]  shift   = (e < 0) ? 5'd0 :
                          (e > 30) ? 5'd31 :
                          e[4:0];
    wire [31:0] mag     = sig_ext[54:23] >> (5'd23 - (e > 23 ? 5'd23 : shift));

    // Properly: integer = sig >> (23 - e) when e <= 23, or sig << (e-23) when e > 23
    wire [31:0] mag_v2;
    assign mag_v2 = (e < 9'sd0)  ? 32'd0 :
                    (e <= 9'sd23) ? ({1'b1, man, 8'b0} >> (8'd23 - e[7:0])) >> 8 :
                                    ({1'b1, man} << (e[4:0] - 5'd23));

    wire overflow_pos = (!sign) && (e >= 9'sd31);
    wire overflow_neg = ( sign) && (e > 9'sd31);

    assign result = is_nan | is_inf | overflow_pos ? 32'h7FFFFFFF :
                    overflow_neg                    ? 32'h80000000 :
                    is_zero | (e < 0)               ? 32'd0        :
                    sign                            ? (~mag_v2 + 1) :  // two's complement negate
                                                       mag_v2;
endmodule


module int_to_fp32 (
    input  [31:0] a,
    output [31:0] result
);
    wire        sign  = a[31];
    wire [31:0] mag   = sign ? (~a + 1) : a;   // absolute value

    // Leading-zero count of 32-bit magnitude
    function [4:0] clz32;
        input [31:0] v;
        integer k;
        begin
            clz32 = 32;
            for (k = 31; k >= 0; k = k - 1)
                if (v[k] && clz32 == 32) clz32 = 31 - k;
        end
    endfunction

    wire [4:0] lz   = clz32(mag);
    wire       zero = (mag == 32'd0);

    // Shift mag left so MSB is at bit 31
    wire [31:0] norm = mag << lz;

    // Biased exponent: 127 + 31 - lz
    wire [7:0] exp_out = 8'd158 - {3'b0, lz};

    // 23-bit mantissa from bits [30:8] of normalised magnitude
    wire [22:0] mant = norm[30:8];
    // GRS for rounding
    wire g = norm[7];
    wire r = norm[6];
    wire s = |norm[5:0];
    wire round_up = g & (r | s | mant[0]);
    wire [23:0] mant_r = {1'b0, mant} + (round_up ? 24'd1 : 24'd0);
    wire        ovf    = mant_r[23];
    wire [22:0] mant_f = mant_r[22:0];
    wire [7:0]  exp_f  = exp_out + (ovf ? 8'd1 : 8'd0);

    assign result = zero ? 32'd0 : {sign, exp_f, mant_f};
endmodule
