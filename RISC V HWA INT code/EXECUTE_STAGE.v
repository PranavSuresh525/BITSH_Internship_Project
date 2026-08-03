`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/13/2024 06:48:56 PM
// Design Name: 
// Module Name: EXECUTE_STAGE
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


module EXECUTE_STAGE(

input [31:0]pc,
input [31:0]rs1,//forwarding already taken care
input [31:0]rs2,//forwarding already taken care
input [31:0]imm,
input [6:0] ex_control,
input [2:0]funct_3,
input [6:0]funct_7,

output [31:0]result,
output [31:0]branch_address,
output branch
    );
    
    wire [31:0]alu_input_1;
    wire [31:0]alu_input_2;
    wire [3:0]alu_control;
    wire branch_cond;
    wire [1:0] alu_op=ex_control[2:1];
    
    MUX_3_TO_1 m1(pc,0,rs1,ex_control[6:5],alu_input_1);
    
    MUX_3_TO_1 m2(rs2,imm,32'd4,ex_control[4:3],alu_input_2);
    
    ALU_CONTROL ac1(alu_op,funct_3,funct_7,alu_control);
    
    ALU a1(alu_input_1,alu_input_2,alu_control,result);
    
   BRANCH_CONDITION_CHECKER b1(alu_input_1,alu_input_2,funct_3,branch_cond);
   
   assign branch=ex_control[0] & branch_cond;
   assign branch_address=pc+imm;
    
endmodule
