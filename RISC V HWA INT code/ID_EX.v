`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/13/2024 06:30:30 PM
// Design Name: 
// Module Name: ID_EX
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module ID_EX(
input clk,
input reset,
input stall,

input branch,

input [4:0]id_rd,
input [31:0]id_pc,
input [31:0]id_rs1,
input [31:0]id_rs2,
input [31:0]id_immediate,

input [2:0]id_funct_3,
input [6:0]id_funct_7,

input [6:0]id_ex_control,
input [1:0]id_mem_control,
input [1:0]id_wb_control,

input [4:0]id_Rs1,
input [4:0]id_Rs2,
input [6:0]id_opcode,

output reg[4:0] ex_rd,
output reg[31:0]ex_pc,
output reg[31:0]ex_rs1,
output reg[31:0]ex_rs2,
output reg[31:0]ex_immediate,
      
output reg [2:0]ex_funct_3,
output reg [6:0]ex_funct_7,

output reg[6:0]ex_ex_control,
output reg[1:0]ex_mem_control,
output reg[1:0]ex_wb_control,

output reg [4:0]ex_Rs1,
output reg [4:0]ex_Rs2,
output reg [6:0]ex_opcode
    ); 

        always @(posedge clk) begin
        if (reset | branch) begin
            ex_rd <= 0;
            ex_pc <= 0;
            ex_rs1 <= 0;
            ex_rs2 <= 0;
            ex_immediate <= 0;
            ex_funct_3 <= 0;
            ex_funct_7 <= 0;
            ex_ex_control <= 0;
            ex_mem_control <= 0;
            ex_wb_control <= 0;
            ex_Rs1 <= 0;
            ex_Rs2 <= 0;
            ex_opcode <= 0;
        end else if (!stall) begin   // ← ONLY UPDATE WHEN NOT STALLED
            ex_rd <= id_rd;
            ex_pc <= id_pc;
            ex_rs1 <= id_rs1;
            ex_rs2 <= id_rs2;
            ex_immediate <= id_immediate;
            ex_funct_3 <= id_funct_3;
            ex_funct_7 <= id_funct_7;
            ex_ex_control <= id_ex_control;
            ex_mem_control <= id_mem_control;
            ex_wb_control <= id_wb_control;
            ex_Rs1 <= id_Rs1;
            ex_Rs2 <= id_Rs2;
            ex_opcode <= id_opcode;
        end
        end
endmodule
