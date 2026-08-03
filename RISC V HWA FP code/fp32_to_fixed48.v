module fp32_to_fixed48 #(
    parameter WIDTH = 48,
    parameter FRAC_BITS = 16
)(
    input  [31:0] fp32_in,
    output [WIDTH-1:0] fixed_out
);
    wire sign = fp32_in[31];
    wire [7:0] exp = fp32_in[30:23];
    wire [22:0] frac = fp32_in[22:0];
    
    wire [23:0] mantissa = (exp == 0) ? 24'd0 : {1'b1, frac};
    
    wire signed [9:0] shift = $signed({2'b0, exp}) - 10'sd150 + FRAC_BITS;
    wire [WIDTH-2:0] abs_fixed;
    
    assign abs_fixed = (shift >= 0) ? ({23'b0, mantissa} << shift) : ({23'b0, mantissa} >> (-shift));
    assign fixed_out = sign ? -$signed({1'b0, abs_fixed}) : {1'b0, abs_fixed};
endmodule