`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// pe (integer / fixed-point version)
//
// Port-for-port match with pe_bf16.v so the two designs are directly
// comparable in a systolic array: same weight-stationary load mechanism
// (weight_load_en + weight_in, no weight_out shift-through), same
// per-PE act_valid_in -> act_valid_out pipeline (instead of the old
// design's single array-wide valid-shift-register), same single-cycle
// latency from act_valid_in to act_valid_out/d_out.
//
// Math is plain signed fixed-point (Q-format assumed consistent across
// act_in/weight_in) instead of pe_bf16's bf16-multiply + custom-format
// accumulate -- this is the only functional difference between the two
// PEs; everything else (interface, timing, control) is identical.
//////////////////////////////////////////////////////////////////////////////
module pe #(
    parameter ACC_WIDTH = 32   // accumulator width (headroom for N partial sums)
)(
    input                      clk,
    input                      rst,

    input                      weight_load_en,
    input      [15:0]          weight_in,

    input                      act_valid_in,
    input      [15:0]          act_in,
    input      [ACC_WIDTH-1:0] d_in,

    output reg                 act_valid_out,
    output reg [15:0]          act_out,
    output reg [ACC_WIDTH-1:0] d_out
);

    // ── STATIONARY WEIGHT REGISTER ──
    reg signed [15:0] weight_reg;
    always @(posedge clk) begin
        if (rst)                     weight_reg <= 16'sd0;
        else if (weight_load_en)     weight_reg <= weight_in;
    end

    // ── COMBINATIONAL FIXED-POINT MULTIPLY ──
    wire signed [15:0] safe_act_in = act_valid_in ? act_in : 16'sd0;
    wire signed [31:0] raw_product = safe_act_in * weight_reg;

    // Sign-extend/pack the 32-bit product into the accumulator width.
    wire signed [ACC_WIDTH-1:0] product =
        (ACC_WIDTH >= 32) ? {{(ACC_WIDTH-32){raw_product[31]}}, raw_product}
                          : raw_product[ACC_WIDTH-1:0];

    // ── SINGLE CYCLE REGISTER (mirrors pe_bf16.v exactly) ──
    always @(posedge clk) begin
        if (rst) begin
            d_out         <= {ACC_WIDTH{1'b0}};
            act_valid_out <= 1'b0;
            act_out       <= 16'd0;
        end else begin
            act_valid_out <= act_valid_in;
            d_out         <= act_valid_in ? (d_in + product) : d_in;
            if (act_valid_in) act_out <= act_in;
        end
    end

endmodule