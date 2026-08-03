`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// CONTROL_UNIT.v  –  RV32I + RV32F subset
//
// ex_control[6:0] = {pc_or_reg_or_0_select[1:0], imm_or_4_sel[1:0],
//                    alu_op[1:0], branch}
//
// New opcodes added:
//   7'b0000111  FLW   – FP load  (same datapath as LW, different opcode)
//   7'b0100111  FSW   – FP store (same datapath as SW)
//   7'b1010011  OP-FP – FP arithmetic/compare/convert/move
//   7'b1000011  FMADD.S  (fused mul-add, decoded but limited: treated
//               as two-instruction sequence in firmware; here we route
//               it like OP-FP with alu_op=arith so ALU_CONTROL can see it)
//////////////////////////////////////////////////////////////////////////////////
module CONTROL_UNIT (
    input  [6:0] opcode,

    output reg [6:0] ex_control,   // {pc_sel[1:0], imm_sel[1:0], alu_op[1:0], branch}
    output reg [1:0] mem_control,  // {mem_read, mem_write}
    output reg [1:0] wb_control,   // {mem_data_select, reg_write}
    output reg       unrecognized
);

    // ALU input-1 select
    parameter pc     = 2'b00;
    parameter zero   = 2'b01;
    parameter reg_s1 = 2'b10;

    // ALU input-2 select
    parameter reg_s2 = 2'b00;
    parameter imm    = 2'b01;
    parameter four   = 2'b10;

    // ALU op
    parameter ld_str = 2'b00;
    parameter brch   = 2'b01;
    parameter arith  = 2'b10;
    parameter im_op  = 2'b11;

    always @(*) begin
        case (opcode)
            //----------------------------------------------------------
            7'b0110011: begin   // R-type integer
                ex_control  = {reg_s1, reg_s2, arith, 1'b0};
                mem_control = 2'b00;
                wb_control  = 2'b01;
                unrecognized = 1'b0;
            end
            //----------------------------------------------------------
            7'b0010011: begin   // I-type integer
                ex_control  = {reg_s1, imm, im_op, 1'b0};
                mem_control = 2'b00;
                wb_control  = 2'b01;
                unrecognized = 1'b0;
            end
            //----------------------------------------------------------
            7'b0000011: begin   // LW (integer load)
                ex_control  = {reg_s1, imm, ld_str, 1'b0};
                mem_control = 2'b10;
                wb_control  = 2'b11;
                unrecognized = 1'b0;
            end
            //----------------------------------------------------------
            7'b0000111: begin   // FLW  (FP load – identical datapath to LW)
                ex_control  = {reg_s1, imm, ld_str, 1'b0};
                mem_control = 2'b10;
                wb_control  = 2'b11;
                unrecognized = 1'b0;
            end
            //----------------------------------------------------------
            7'b0100011: begin   // SW (integer store)
                ex_control  = {reg_s1, imm, ld_str, 1'b0};
                mem_control = 2'b01;
                wb_control  = 2'b00;
                unrecognized = 1'b0;
            end
            //----------------------------------------------------------
            7'b0100111: begin   // FSW  (FP store – identical datapath to SW)
                ex_control  = {reg_s1, imm, ld_str, 1'b0};
                mem_control = 2'b01;
                wb_control  = 2'b00;
                unrecognized = 1'b0;
            end
            //----------------------------------------------------------
            7'b1100011: begin   // Branch
                ex_control  = {reg_s1, reg_s2, brch, 1'b1};
                mem_control = 2'b00;
                wb_control  = 2'b00;
                unrecognized = 1'b0;
            end
            //----------------------------------------------------------
            7'b1101111: begin   // JAL
                ex_control  = {pc, four, ld_str, 1'b0};
                mem_control = 2'b00;
                wb_control  = 2'b01;
                unrecognized = 1'b0;
            end
            //----------------------------------------------------------
            7'b1100111: begin   // JALR
                ex_control  = {reg_s1, imm, ld_str, 1'b0};
                mem_control = 2'b00;
                wb_control  = 2'b01;
                unrecognized = 1'b0;
            end
            //----------------------------------------------------------
            7'b0110111: begin   // LUI
                ex_control  = {zero, imm, ld_str, 1'b0};
                mem_control = 2'b00;
                wb_control  = 2'b01;
                unrecognized = 1'b0;
            end
            //----------------------------------------------------------
            7'b0010111: begin   // AUIPC
                ex_control  = {pc, imm, ld_str, 1'b0};
                mem_control = 2'b00;
                wb_control  = 2'b01;
                unrecognized = 1'b0;
            end
            //----------------------------------------------------------
            7'b1010011: begin   // OP-FP  (fadd/fsub/fmul/fmin/fmax/fcmp/fcvt/fmv/fsgnj)
                // rs1 and rs2 both come from register file (fp regs mapped
                // onto the shared 32-entry GPR bank).
                // Result written back to rd.  No memory access.
                ex_control  = {reg_s1, reg_s2, arith, 1'b0};
                mem_control = 2'b00;
                wb_control  = 2'b01;
                unrecognized = 1'b0;
            end
            //----------------------------------------------------------
            7'b1000011: begin   // FMADD.S  (fused mul-add)
                // Not natively fused here: firmware must use explicit
                // fmul + fadd. Route same as OP-FP so ALU_CONTROL can
                // see the funct5 in funct_7.
                ex_control  = {reg_s1, reg_s2, arith, 1'b0};
                mem_control = 2'b00;
                wb_control  = 2'b01;
                unrecognized = 1'b0;
            end
            //----------------------------------------------------------
            7'b0001011: begin   // Custom HWA instruction
                ex_control  = {reg_s1, reg_s2, ld_str, 1'b0};
                mem_control = 2'b00;
                wb_control  = 2'b01;
                unrecognized = 1'b0;
            end
            //----------------------------------------------------------
            default: begin
                ex_control  = 7'd0;
                mem_control = 2'b00;
                wb_control  = 2'b00;
                unrecognized = 1'b1;
            end
        endcase
    end

endmodule
