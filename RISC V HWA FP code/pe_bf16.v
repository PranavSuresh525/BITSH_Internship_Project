`timescale 1ns / 1ps

module pe_bf16 #(
    parameter ACC_WIDTH  = 32,
    parameter FRAC_BITS  = 16,
    parameter MANT_WIDTH = 16   
)(
    input         clk,
    input         rst,
    input         weight_load_en,
    input  [15:0] weight_in,
    input         act_valid_in,
    input  [15:0] act_in,
    input  [ACC_WIDTH-1:0] d_in,
    output reg        act_valid_out,
    output reg [15:0] act_out,
    (* use_dsp = "yes" *) output reg [ACC_WIDTH-1:0] d_out
);

    reg [15:0] weight_reg;
    always @(posedge clk) begin
        if (rst)                 weight_reg <= 16'd0;
        else if (weight_load_en) weight_reg <= weight_in;
    end

    // --- FULLY COMBINATIONAL SQUASHED MATH ---
    wire [15:0] safe_act_in = act_valid_in ? act_in : 16'd0;
    wire [31:0] fp32_product_comb;
    bf16_mul_fp32 u_mult (.a(safe_act_in), .b(weight_reg), .result(fp32_product_comb));

    wire        prod_sign = fp32_product_comb[31];
    wire [7:0]  prod_exp  = fp32_product_comb[30:23];
    wire [22:0] prod_frac = fp32_product_comb[22:0];

    localparam DROP = 24 - MANT_WIDTH;
    wire [MANT_WIDTH-1:0] prod_mantissa = (prod_exp == 0) ? {MANT_WIDTH{1'b0}} : {1'b1, prod_frac[22 -: (MANT_WIDTH-1)]};
    wire signed [9:0] prod_shift = $signed({2'b0, prod_exp}) - 10'sd150 + FRAC_BITS + DROP;

    localparam MAX_LSHIFT = ACC_WIDTH - 1;
    localparam MAX_RSHIFT = MANT_WIDTH;
    localparam DW_WIDTH  = MANT_WIDTH + MAX_LSHIFT;
    localparam RSHIFT_W  = $clog2(DW_WIDTH + 1);

    wire [DW_WIDTH-1:0] dw_comb = {prod_mantissa, {MAX_LSHIFT{1'b0}}};
    wire signed [RSHIFT_W:0] rshift_comb = MAX_LSHIFT - prod_shift;
    wire [DW_WIDTH-1:0] dw_shifted_comb = dw_comb >> rshift_comb[RSHIFT_W-1:0];

    reg [ACC_WIDTH-2:0] abs_fixed_comb;
    always @(*) begin
        if ((prod_shift < -MAX_RSHIFT) || (prod_shift > MAX_LSHIFT))
            abs_fixed_comb = {(ACC_WIDTH-1){1'b0}};
        else
            abs_fixed_comb = dw_shifted_comb[ACC_WIDTH-2:0];
    end

    wire [ACC_WIDTH-1:0] fixed_product_comb = prod_sign ? -$signed({1'b0, abs_fixed_comb}) : {1'b0, abs_fixed_comb};

    // --- SINGLE CYCLE REGISTER ---
    always @(posedge clk) begin
        if (rst) begin
            d_out         <= {ACC_WIDTH{1'b0}};
            act_valid_out <= 1'b0;
            act_out       <= 16'd0;
        end else begin
            act_valid_out <= act_valid_in;
            d_out         <= act_valid_in ? (d_in + fixed_product_comb) : d_in;
            if (act_valid_in) act_out <= act_in;
        end
    end
endmodule