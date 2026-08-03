`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// SIGN_EXTEND.v  –  RV32I + RV32F immediate decoding
//
// New cases:
//   7'b0000111  FLW  – 12-bit signed immediate (same as LW)
//   7'b0100111  FSW  – split immediate like SW  {inst[31:25], inst[11:7]}
//   7'b1010011  OP-FP – no immediate (rs2 field reused for opcode variants;
//               sign_ext_imm tied to 0 so ALU gets a clean second input
//               from the register file via the mux)
//   7'b1100111  JALR – 12-bit signed immediate
//   7'b1101111  JAL  – 21-bit signed immediate (J-type)
//////////////////////////////////////////////////////////////////////////////////
module SIGN_EXTEND (
    input  [31:0] instruction,
    output reg [31:0] sign_ext_imm
);

    always @(*) begin
        case (instruction[6:0])
            //----------------------------------------------------------
            // I-type integer ALU
            7'b0010011: begin
                case (instruction[14:12])
                    3'b011:  sign_ext_imm = {20'b0, instruction[31:20]}; // SLTIU (unsigned)
                    default: sign_ext_imm = {{20{instruction[31]}}, instruction[31:20]};
                endcase
            end
            //----------------------------------------------------------
            // LW  (integer load)
            7'b0000011: sign_ext_imm = {{20{instruction[31]}}, instruction[31:20]};
            //----------------------------------------------------------
            // FLW (FP load – identical immediate encoding to LW)
            7'b0000111: sign_ext_imm = {{20{instruction[31]}}, instruction[31:20]};
            //----------------------------------------------------------
            // JALR
            7'b1100111: sign_ext_imm = {{20{instruction[31]}}, instruction[31:20]};
            //----------------------------------------------------------
            // SW (integer store)
            7'b0100011: sign_ext_imm = {{20{instruction[31]}},
                                         instruction[31:25],
                                         instruction[11:7]};
            //----------------------------------------------------------
            // FSW (FP store – same split-immediate as SW)
            7'b0100111: sign_ext_imm = {{20{instruction[31]}},
                                         instruction[31:25],
                                         instruction[11:7]};
            //----------------------------------------------------------
            // Branch (B-type)
            7'b1100011: begin
                case (instruction[14:12])
                    3'b110, 3'b111: // BLTU, BGEU – zero-extended offset
                        sign_ext_imm = {19'b0,
                                        instruction[31],
                                        instruction[7],
                                        instruction[30:25],
                                        instruction[11:8],
                                        1'b0};
                    default:        // BEQ, BNE, BLT, BGE – sign-extended
                        sign_ext_imm = {{19{instruction[31]}},
                                        instruction[31],
                                        instruction[7],
                                        instruction[30:25],
                                        instruction[11:8],
                                        1'b0};
                endcase
            end
            //----------------------------------------------------------
            // LUI / AUIPC (U-type)
            7'b0110111,
            7'b0010111: sign_ext_imm = {instruction[31:12], 12'b0};
            //----------------------------------------------------------
            // JAL (J-type)
            7'b1101111: sign_ext_imm = {{11{instruction[31]}},
                                         instruction[31],
                                         instruction[19:12],
                                         instruction[20],
                                         instruction[30:21],
                                         1'b0};
            //----------------------------------------------------------
            // OP-FP: no meaningful immediate; rs2 comes from reg file
            7'b1010011: sign_ext_imm = 32'd0;
            //----------------------------------------------------------
            default: sign_ext_imm = 32'd0;
        endcase
    end

endmodule
