`timescale 1ns / 1ps

module bf16_mul_fp32 (
    input  [15:0] a,
    input  [15:0] b,
    output [31:0] result
);

    wire        sign_a = a[15];
    wire        sign_b = b[15];
    wire [7:0]  exp_a  = a[14:7];
    wire [7:0]  exp_b  = b[14:7];
    wire [6:0]  man_a  = a[6:0];
    wire [6:0]  man_b  = b[6:0];

    wire a_is_zero = (exp_a == 8'd0);
    wire b_is_zero = (exp_b == 8'd0);

    wire [7:0] sig_a = {1'b1, man_a};
    wire [7:0] sig_b = {1'b1, man_b};

    wire result_sign = sign_a ^ sign_b;

    // exact 16-bit product, binary point conceptually after bit 14
   (* use_dsp = "yes" *) wire [15:0] prod = sig_a * sig_b;

    wire signed [9:0] exp_sum = $signed({2'b0, exp_a}) + $signed({2'b0, exp_b}) - 10'sd127;

    wire        shift1 = prod[15];
    wire signed [9:0] exp_adj = exp_sum + (shift1 ? 10'sd1 : 10'sd0);

    wire [22:0] mant_fp32 = shift1 ? {prod[14:0], 8'b0} : {prod[13:0], 9'b0};

    wire underflow = (exp_adj <= 0);
    wire overflow  = (exp_adj >= 255);

    assign result = (a_is_zero | b_is_zero) ? {result_sign, 31'd0} :
                    underflow               ? {result_sign, 31'd0} :
                    overflow                ? {result_sign, 8'hFE, 23'h7FFFFF} :
                                               {result_sign, exp_adj[7:0], mant_fp32};

endmodule
