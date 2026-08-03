`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// ALU_CONTROL.v
//
// alu_op encoding (from CONTROL_UNIT):
//   2'b00  ld_str   – ADD for address calculation
//   2'b01  brch     – pass-through (branch comparisons go to BCC directly)
//   2'b10  arith    – R-type integer (use funct3 + funct7)
//   2'b11  im_op    – I-type integer immediate (use funct3 only)
//   + new:
//   2'b10 + opcode hint via funct_7[6:2] == funct5 for OP-FP (1010011)
//
// The EXECUTE_STAGE passes the raw instruction [31:25] as funct_7.
// For OP-FP instructions the funct_7[6:2] field is funct5 (operation),
// and funct_7[1:0] is fmt (00 = single-precision). We decode funct5 here.
//
// Output alu_control codes (5 bits):
//   Integer: 0-10  (unchanged from original 4-bit set)
//   FP32:   11-25  (new)
//////////////////////////////////////////////////////////////////////////////////
module ALU_CONTROL (
    input  [1:0] alu_op,
    input  [2:0] funct_3,
    input  [6:0] funct_7,   // bits [31:25] of instruction
    input  [6:0] fp_opcode, // raw opcode passed from EXECUTE_STAGE
    output reg [4:0] alu_control
);

    // funct5 for OP-FP decoding
    wire [4:0] funct5 = funct_7[6:2];

    always @(*) begin
        case (alu_op)
            //----------------------------------------------------------
            2'b00: alu_control = 5'd0;   // ADD (load/store address)
            //----------------------------------------------------------
            2'b01: alu_control = 5'd10;  // branch: pass-through (BCC handles compare)
            //----------------------------------------------------------
            2'b10: begin  // R-type integer OR OP-FP
                if (fp_opcode == 7'b1010011) begin
                    // OP-FP: decode by funct5
                    case (funct5)
                        5'b00000: alu_control = 5'd11; // FADD.S
                        5'b00001: alu_control = 5'd12; // FSUB.S
                        5'b00010: alu_control = 5'd13; // FMUL.S
                        5'b00100: begin                 // FSGNJ family
                            case (funct_3)
                                3'b000: alu_control = 5'd23; // FSGNJ.S
                                3'b001: alu_control = 5'd24; // FSGNJN.S
                                3'b010: alu_control = 5'd25; // FSGNJX.S
                                default: alu_control = 5'd0;
                            endcase
                        end
                        5'b00101: begin                 // FMIN/FMAX
                            case (funct_3)
                                3'b000: alu_control = 5'd14; // FMIN.S
                                3'b001: alu_control = 5'd15; // FMAX.S
                                default: alu_control = 5'd0;
                            endcase
                        end
                        5'b10100: begin                 // FEQ/FLT/FLE
                            case (funct_3)
                                3'b010: alu_control = 5'd16; // FEQ.S
                                3'b001: alu_control = 5'd17; // FLT.S
                                3'b000: alu_control = 5'd18; // FLE.S
                                default: alu_control = 5'd0;
                            endcase
                        end
                        5'b11000: alu_control = 5'd19; // FCVT.W.S  (rs2=00000)
                        5'b11010: alu_control = 5'd20; // FCVT.S.W  (rs2=00000)
                        5'b11100: begin
                            if (funct_3 == 3'b000)
                                alu_control = 5'd21;   // FMV.X.W
                            else
                                alu_control = 5'd0;    // FCLASS (not implemented)
                        end
                        5'b11110: alu_control = 5'd22; // FMV.W.X
                        default:  alu_control = 5'd0;
                    endcase
                end else begin
                    // Standard R-type integer
                    case (funct_3)
                        3'd0: case (funct_7)
                                7'b0000000: alu_control = 5'd0;  // ADD
                                7'b0100000: alu_control = 5'd1;  // SUB
                                default:    alu_control = 5'd0;
                              endcase
                        3'd4: alu_control = 5'd2;  // XOR
                        3'd6: alu_control = 5'd3;  // OR
                        3'd7: alu_control = 5'd4;  // AND
                        3'd1: alu_control = 5'd5;  // SLL
                        3'd5: case (funct_7)
                                7'b0000000: alu_control = 5'd6;  // SRL
                                7'b0100000: alu_control = 5'd7;  // SRA
                                default:    alu_control = 5'd0;
                              endcase
                        3'd2: alu_control = 5'd8;  // SLT
                        3'd3: alu_control = 5'd9;  // SLTU
                        default: alu_control = 5'd10;
                    endcase
                end
            end
            //----------------------------------------------------------
            2'b11: begin  // I-type immediate integer
                case (funct_3)
                    3'd0: alu_control = 5'd0;  // ADDI
                    3'd4: alu_control = 5'd2;  // XORI
                    3'd6: alu_control = 5'd3;  // ORI
                    3'd7: alu_control = 5'd4;  // ANDI
                    3'd1: alu_control = 5'd5;  // SLLI
                    3'd5: case (funct_7)
                            7'b0000000: alu_control = 5'd6;  // SRLI
                            7'b0100000: alu_control = 5'd7;  // SRAI
                            default:    alu_control = 5'd0;
                          endcase
                    3'd2: alu_control = 5'd8;  // SLTI
                    3'd3: alu_control = 5'd9;  // SLTIU
                    default: alu_control = 5'd0;
                endcase
            end
            //----------------------------------------------------------
            default: alu_control = 5'd0;
        endcase
    end

endmodule
