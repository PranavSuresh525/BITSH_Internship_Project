`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// EXECUTE_STAGE.v  –  RV32I + RV32F
//
// Changes vs original:
//   1. ALU_CONTROL now outputs 5-bit alu_control (was 4-bit).
//   2. ALU now takes 5-bit control and instantiates FP32 sub-modules.
//   3. ALU_CONTROL receives fp_opcode (= ex_opcode from ID/EX register)
//      so it can distinguish OP-FP (7'b1010011) from integer R-type
//      when alu_op == 2'b10.
//   4. Everything else (branch address, BCC, muxes) is unchanged.
//////////////////////////////////////////////////////////////////////////////////
module EXECUTE_STAGE (
    input  [31:0] pc,
    input  [31:0] rs1,       // after forwarding muxes
    input  [31:0] rs2,       // after forwarding muxes
    input  [31:0] imm,
    input  [6:0]  ex_control,
    input  [2:0]  funct_3,
    input  [6:0]  funct_7,
    input  [6:0]  opcode,    // raw opcode – passed to ALU_CONTROL

    output [31:0] result,
    output [31:0] branch_address,
    output        branch
);

    wire [31:0] alu_input_1;
    wire [31:0] alu_input_2;
    wire [4:0]  alu_control;         // widened to 5 bits
    wire        branch_cond;
    wire [1:0]  alu_op = ex_control[2:1];

    MUX_3_TO_1 m1 (pc, 32'd0, rs1, ex_control[6:5], alu_input_1);
    MUX_3_TO_1 m2 (rs2, imm, 32'd4, ex_control[4:3], alu_input_2);

    ALU_CONTROL ac1 (
        .alu_op    (alu_op),
        .funct_3   (funct_3),
        .funct_7   (funct_7),
        .fp_opcode (opcode),
        .alu_control(alu_control)
    );

    ALU a1 (
        .a       (alu_input_1),
        .b       (alu_input_2),
        .control (alu_control),
        .c       (result)
    );

    BRANCH_CONDITION_CHECKER b1 (
        .input1     (alu_input_1),
        .input2     (alu_input_2),
        .funct_3    (funct_3),
        .branch_cond(branch_cond)
    );

    assign branch         = ex_control[0] & branch_cond;
    assign branch_address = pc + imm;

endmodule
